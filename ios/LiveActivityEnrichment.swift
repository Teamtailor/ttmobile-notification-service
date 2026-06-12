import ActivityKit
import Foundation
import UIKit
import os

// ActivityKit matches Live Activities by the UNQUALIFIED type name of the
// ActivityAttributes struct — the same string a push-to-start payload carries in
// its `attributes-type` field — not by Swift type identity. expo-widgets'
// LiveActivityAttributes is internal to its pod, so this shape-identical
// duplicate gives this pod an independent handle on the SAME activities (the
// main app and the widget extension already rely on this name matching to share
// activities across targets). ContentState must stay field-identical to
// expo-widgets' definition: { name: String, props: String }.
//
// PROVEN ON DEVICE (iOS 26.5): `.activities` enumeration, `.update()` AND
// `activityUpdates` all work through this duplicate. Caveat: if two same-named
// attributes types ever iterate `activityUpdates` in one process, only the most
// recently registered iterator receives events (this starved the enricher while
// the expo-widgets patch carried its own observer — since removed; keep this
// pod's iterator the ONLY one).
@available(iOS 16.2, *)
struct LiveActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var name: String
    var props: String
  }
}

/// Enriches push-started Live Activities with E2E-encrypted PII entirely on the
/// native side, during the background wake an ActivityKit push-to-start grants
/// ("to download assets that the Live Activity needs", per Apple) — no JS, no
/// React, no bridge.
///
/// How activities reach the enricher (two paths, deduped by activity id):
/// 1. LAUNCH ENUMERATION — `Activity<LiveActivityAttributes>.activities` at
///    `didFinishLaunching`. Covers the production wake: a push-to-start
///    launches the terminated app and the activity already exists.
/// 2. `activityUpdates` ITERATION — covers activities that start while the app
///    is already running. This pod owns the process's ONLY iterator (the
///    expo-widgets observer that used to starve it was removed from the patch
///    2026-06-12; see the attributes-type comment above).
///
/// Pipeline, per newly seen activity:
/// 1. Parse the content-state `props` JSON and extract its `encrypted_data` field — a
///    `MobileNotifications::PayloadEncryptor` blob `{encrypted_key, cipher_text,
///    nonce, tag}` (all strict base64), encrypted against this device's
///    registered public key.
/// 2. Decrypt with `CryptoUtils.hybridDecrypt` (same pod, same key the NSE
///    uses) into a JSON object of PII fields, e.g. `{candidateName, avatarUrl}`.
/// 3. Download `avatarUrl` (https) into the app-group container under
///    `ExpoWidgets/` so the widget extension can read it.
/// 4. Stage the enrichment in app-group UserDefaults under
///    `__tt_la_enrichment_<meetingEventId>` — the widget extension merges it
///    into props at render time, which keeps enrichment alive even if a later
///    APNs channel update replaces the content-state wholesale (the app is NOT
///    woken for those, so only a render-time merge survives a clobber).
/// 5. Update the activity with the enriched props merged in (preserving
///    staleDate and relevanceScore) to trigger an immediate re-render.
///
/// The decryption key is `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: a
/// wake between reboot and first unlock cannot decrypt. That's a deliberate
/// fallback — the widget renders its non-PII state ("Meeting" eyebrow, no
/// avatar) and a later launch retries, since failed activities are not marked
/// as enriched.
@available(iOS 16.2, *)
public actor LiveActivityEnricher {
  public static let shared = LiveActivityEnricher()

  // Notice-level os.Logger lines
  // are persisted to the device log store, so a background/terminated wake can
  // be verified retroactively with `log collect --device`. Values are .public —
  // unified logging redacts dynamics by default. Never log decrypted values.
  private let log = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "ttmobile-notification-service",
    category: "LA-enrich"
  )

  private var observerTask: Task<Void, Never>?
  private var enrichedActivityIds = Set<String>()
  private var contentProbeTasks: [String: Task<Void, Never>] = [:]

  private static let stagingKeyPrefix = "__tt_la_enrichment_"
  private static let avatarFilePrefix = "la-avatar-"

  private init() {}

  /// Idempotent. Called from the app-delegate subscriber on every launch —
  /// including background launches triggered by a push-to-start notification.
  public func start() {
    guard observerTask == nil else { return }
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      log.notice("Live Activities disabled — enrichment observer not started")
      return
    }

    log.notice("starting enrichment observer (existing activities: \(Activity<LiveActivityAttributes>.activities.count, privacy: .public))")

    observerTask = Task {
      pruneStaleEnrichment()
      for activity in Activity<LiveActivityAttributes>.activities {
        await enrich(activity)
      }
      log.notice("own activityUpdates iteration starting")
      for await activity in Activity<LiveActivityAttributes>.activityUpdates {
        log.notice("own activityUpdates yielded \(activity.id, privacy: .public)")
        await enrich(activity)
      }
      log.notice("own activityUpdates iteration ENDED")
    }
  }

  // PROBE: app-process visibility of remote Live Activity updates. Every
  // content-state change this process observes logs a persisted line. The
  // experiment for "does a channel broadcast wake the app?": force-quit the
  // app, send a broadcast, watch the card re-render — then `log collect
  // --device` and compare categories. An `LA-render` line (widget process,
  // LiveActivityRenderEnrichment) WITHOUT a matching `LA-enrich` "saw content
  // update" line at that timestamp is empirical proof the update rendered
  // without waking the app. While the app IS alive, lines here also show
  // local update() calls — match timestamps when reading the log.
  private func probeContentUpdates(_ activity: Activity<LiveActivityAttributes>) {
    guard contentProbeTasks[activity.id] == nil else { return }

    contentProbeTasks[activity.id] = Task { [log] in
      for await content in activity.contentUpdates {
        log.notice("app-process saw content update for \(activity.id, privacy: .public) (staleDate: \(content.staleDate.map { "\($0)" } ?? "nil", privacy: .public))")
      }
      log.notice("app-process content updates ENDED for \(activity.id, privacy: .public)")
    }
  }

  // MARK: - Enrichment pipeline

  private func enrich(_ activity: Activity<LiveActivityAttributes>) async {
    probeContentUpdates(activity)
    guard !enrichedActivityIds.contains(activity.id) else { return }

    let state = activity.content.state
    guard var props = parseJSONObject(state.props) else {
      log.error("activity \(activity.id, privacy: .public): props is not a JSON object — skipping")
      enrichedActivityIds.insert(activity.id)
      return
    }

    guard let enc = extractEncryptedBlob(props) else {
      // Not an error: app-started activities (QA tester) and pushes predating
      // backend enrichment simply carry no `encrypted_data`.
      log.notice("activity \(activity.id, privacy: .public): no encrypted_data in props — nothing to enrich")
      enrichedActivityIds.insert(activity.id)
      return
    }

    let plaintext: String
    do {
      plaintext = try CryptoUtils.hybridDecrypt(
        encryptedKey: enc.encryptedKey,
        cipherText: enc.cipherText,
        nonce: enc.nonce,
        tag: enc.tag
      )
    } catch {
      // Most likely reboot-before-first-unlock (key inaccessible) or a stale
      // public key. NOT marked enriched — a later launch retries.
      log.error("activity \(activity.id, privacy: .public): hybridDecrypt failed: \(String(describing: error), privacy: .public)")
      return
    }

    guard var enrichment = parseJSONObject(plaintext) else {
      log.error("activity \(activity.id, privacy: .public): decrypted payload is not a JSON object")
      enrichedActivityIds.insert(activity.id)
      return
    }

    // Stable per-meeting key shared with the render-time merge in the widget
    // extension; the activity id is process-discoverable but absent from props,
    // so it can't key a lookup done from props alone.
    let stagingKey = stableKey(fromProps: props) ?? activity.id

    // Replace the remote avatar URLs with local app-group files the widget
    // extension can load (first candidate + the stacked second one for group
    // meetings). On download failure the field is dropped entirely: the
    // renderer's `uiImage` branch does a synchronous Data(contentsOf:) with
    // whatever URL it gets, and handing it an https URL would mean sync
    // network on the extension's render path.
    for (field, fileSuffix) in [("avatarUrl", ""), ("secondAvatarUrl", "-2")] {
      if let remote = enrichment[field] as? String {
        enrichment[field] = nil
        if let localURL = await downloadAvatar(from: remote, key: stagingKey + fileSuffix) {
          enrichment[field] = localURL.absoluteString
        }
      }
    }

    let hasName = enrichment["candidateName"] != nil
    let hasAvatar = enrichment["avatarUrl"] != nil
    stageEnrichment(enrichment, forKey: stagingKey)

    // Merge into the content-state too and update natively. The staged copy is
    // what survives content-state clobbers (render-time merge); this merge
    // makes the enrichment visible NOW, and `enrichedAt` guards against
    // ActivityKit deduplicating an identical content-state.
    for (key, value) in enrichment {
      props[key] = value
    }
    props["enrichedAt"] = Int(Date().timeIntervalSince1970)

    guard let mergedProps = serializeJSONObject(props) else {
      log.error("activity \(activity.id, privacy: .public): failed to re-serialize enriched props")
      return
    }

    let newState = LiveActivityAttributes.ContentState(name: state.name, props: mergedProps)
    let content = ActivityContent(
      state: newState,
      staleDate: activity.content.staleDate,
      relevanceScore: activity.content.relevanceScore
    )
    await activity.update(content)

    enrichedActivityIds.insert(activity.id)
    log.notice("activity \(activity.id, privacy: .public): enriched (key=\(stagingKey, privacy: .public) name=\(hasName, privacy: .public) avatar=\(hasAvatar, privacy: .public))")
  }

  // MARK: - Encrypted blob extraction

  private struct EncryptedBlob {
    let encryptedKey: String
    let cipherText: String
    let nonce: String
    let tag: String
  }

  /// Accepts `encrypted_data` as either a nested JSON object or a JSON-encoded string
  /// (the NSE's `encrypted_data` ships as a string; the props embedding may
  /// reasonably use either).
  private func extractEncryptedBlob(_ props: [String: Any]) -> EncryptedBlob? {
    var dict = props["encrypted_data"] as? [String: Any]
    if dict == nil, let raw = props["encrypted_data"] as? String {
      dict = parseJSONObject(raw)
    }
    guard let dict,
          let encryptedKey = dict["encrypted_key"] as? String,
          let cipherText = dict["cipher_text"] as? String,
          let nonce = dict["nonce"] as? String,
          let tag = dict["tag"] as? String else {
      return nil
    }
    return EncryptedBlob(encryptedKey: encryptedKey, cipherText: cipherText, nonce: nonce, tag: tag)
  }

  private func stableKey(fromProps props: [String: Any]) -> String? {
    guard let value = props["meetingEventId"] else { return nil }
    if let string = value as? String { return string }
    if let number = value as? NSNumber { return number.stringValue }
    return nil
  }

  // MARK: - Avatar download

  private func downloadAvatar(from urlString: String, key: String) async -> URL? {
    guard let url = URL(string: urlString), let scheme = url.scheme,
          scheme == "https" || scheme == "http" else {
      log.error("avatar url for key \(key, privacy: .public) is not http(s) — dropping")
      return nil
    }
    guard let directory = sharedImagesDirectory() else { return nil }

    let destination = directory.appendingPathComponent("\(Self.avatarFilePrefix)\(key)")
    do {
      let started = Date()
      let (data, response) = try await URLSession.shared.data(from: url)
      if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
        log.error("avatar download for key \(key, privacy: .public) got HTTP \(http.statusCode, privacy: .public)")
        return nil
      }
      let imageData = downscaledImageData(data, maxDimension: 512) ?? data
      try imageData.write(to: destination, options: .atomic)
      let elapsed = Int(Date().timeIntervalSince(started) * 1000)
      log.notice("avatar for key \(key, privacy: .public): \(data.count, privacy: .public) bytes downloaded, \(imageData.count, privacy: .public) bytes written in \(elapsed, privacy: .public)ms")
      return destination
    } catch {
      log.error("avatar download for key \(key, privacy: .public) failed: \(String(describing: error), privacy: .public)")
      return nil
    }
  }

  /// Widget extensions render images within a tight memory budget — a
  /// full-resolution original decodes to tens of MB and WidgetKit drops it
  /// (the activity shows a gray box instead). The backend already requests a
  /// CDN-resized variant; this is the device-side guarantee for anything that
  /// slips through (e.g. social-sourced originals). Re-encodes as JPEG when
  /// downscaling; returns nil (caller keeps the original bytes) when the image
  /// is already small enough or can't be decoded.
  private func downscaledImageData(_ data: Data, maxDimension: CGFloat) -> Data? {
    guard let image = UIImage(data: data) else { return nil }
    let largest = max(image.size.width, image.size.height)
    guard largest > maxDimension else { return nil }

    let scale = maxDimension / largest
    let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let resized = UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: newSize))
    }
    return resized.jpegData(compressionQuality: 0.85)
  }

  /// `<app-group container>/ExpoWidgets/` — the same directory expo-widgets
  /// exposes to JS as `widgetsDirectory` ("shared images for widgets",
  /// readable by both the app and the widget extension).
  private func sharedImagesDirectory() -> URL? {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupIdentifier
    ) else {
      log.error("no app-group container for \(self.appGroupIdentifier, privacy: .public)")
      return nil
    }
    let directory = container.appendingPathComponent("ExpoWidgets", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
      log.error("failed to create shared images directory: \(String(describing: error), privacy: .public)")
      return nil
    }
    return directory
  }

  /// The same Info.plist key WidgetsStorage reads (written by the expo-widgets
  /// config plugin from app.config's `groupIdentifier`), so the staging store
  /// and the widget extension's reader can never drift apart. The fallback is
  /// the group CryptoUtils already hardcodes for the keychain.
  private var appGroupIdentifier: String {
    (Bundle.main.object(forInfoDictionaryKey: "ExpoWidgetsAppGroupIdentifier") as? String)
      ?? "group.com.teamtailor.keys"
  }

  // MARK: - Staging (read by the widget extension's render-time merge)

  private func stageEnrichment(_ enrichment: [String: Any], forKey key: String) {
    guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
      log.error("no app-group UserDefaults for \(self.appGroupIdentifier, privacy: .public)")
      return
    }
    defaults.set(enrichment, forKey: Self.stagingKeyPrefix + key)
  }

  /// Drops staged entries and avatar files whose meeting no longer has a live
  /// activity, so the app-group store doesn't grow without bound. Runs once per
  /// observer start, before enrichment.
  private func pruneStaleEnrichment() {
    guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }

    let activeKeys = Set(
      Activity<LiveActivityAttributes>.activities.map { activity -> String in
        guard let props = parseJSONObject(activity.content.state.props),
              let key = stableKey(fromProps: props) else {
          return activity.id
        }
        return key
      }
    )

    for storedKey in defaults.dictionaryRepresentation().keys
    where storedKey.hasPrefix(Self.stagingKeyPrefix) {
      let key = String(storedKey.dropFirst(Self.stagingKeyPrefix.count))
      if !activeKeys.contains(key) {
        defaults.removeObject(forKey: storedKey)
        log.notice("pruned stale enrichment for key \(key, privacy: .public)")
      }
    }

    guard let directory = sharedImagesDirectory(),
          let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
      return
    }
    for file in files where file.lastPathComponent.hasPrefix(Self.avatarFilePrefix) {
      var key = String(file.lastPathComponent.dropFirst(Self.avatarFilePrefix.count))
      // Second-candidate avatars are stored as la-avatar-<key>-2.
      if key.hasSuffix("-2") {
        key = String(key.dropLast(2))
      }
      if !activeKeys.contains(key) {
        try? FileManager.default.removeItem(at: file)
      }
    }
  }

  // MARK: - JSON helpers

  private func parseJSONObject(_ string: String) -> [String: Any]? {
    guard let data = string.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }

  private func serializeJSONObject(_ object: [String: Any]) -> String? {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object) else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }
}
