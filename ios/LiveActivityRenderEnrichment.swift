import Foundation
import os

// Compiled into the expo-widgets WIDGET-EXTENSION target by this package's
// config plugin — deliberately NOT part of the EncryptionModule pod, because
// render-time code must run in the widget process (see the podspec comment
// for the same split on NotificationService.swift).
//
// expo-widgets' render pipeline looks this class up BY NAME via the ObjC
// runtime (the `ExpoWidgetsLiveActivityPropsTransformer` hook patched into
// its Widgets/Utils.swift) and passes every Live Activity's decoded
// content-state props through `transform(_:)` before evaluating the layout.
// The runtime lookup is what bridges the two separately-compiled modules —
// there is no import path from the ExpoWidgets pod to this target.
//
// The transform re-applies the PII enrichment the main app staged in
// app-group UserDefaults under `__tt_la_enrichment_<meetingEventId>` during
// the push-to-start background wake (candidateName, meetingTitle, local
// file:// avatar URLs, the rich widgetUrl, ...). Broadcast-channel update/end
// pushes replace the content-state wholesale WITHOUT waking the app, so
// without this render-time overlay the first broadcast would wipe the
// enrichment. Staged values win: channel pushes never carry these keys, and
// the plaintext value they do carry (the bare fallback widgetUrl) is exactly
// what staging upgrades.
@objc(ExpoWidgetsLiveActivityPropsTransformer)
public final class LiveActivityRenderEnrichment: NSObject {
  // Same Info.plist key WidgetsStorage reads; the staging side
  // (LiveActivityEnrichment.swift) resolves the suite identically, so reads
  // and writes always hit the same app-group store. The key prefix must match
  // LiveActivityEnrichment.stagingKeyPrefix.
  private static let appGroupIdentifier =
    Bundle.main.object(forInfoDictionaryKey: "ExpoWidgetsAppGroupIdentifier") as? String
  private static let stagingKeyPrefix = "__tt_la_enrichment_"

  // PROBE: every Live Activity render in the WIDGET process logs a persisted
  // notice line (category LA-render). Paired with the app-process probe in
  // LiveActivityEnrichment (category LA-enrich): after a channel broadcast,
  // an LA-render line with no matching LA-enrich "saw content update" line in
  // `log collect --device` proves the update rendered without waking the app.
  // Key COUNT only — never log staged values (PII).
  private static let log = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "ExpoWidgetsTarget",
    category: "LA-render"
  )

  @objc public func transform(_ props: [String: Any]) -> [String: Any] {
    // Stamped by the backend into broadcast props only — a render logging a
    // fresh value IS a delivered channel broadcast; "none" or a stale value is
    // start content or a local re-render (stale-date, countdown, environment).
    let broadcastAt = (props["broadcastAt"] as? NSNumber)?.stringValue
      ?? (props["broadcastAt"] as? String) ?? "none"

    guard
      let meetingEventId = (props["meetingEventId"] as? String)
        ?? (props["meetingEventId"] as? NSNumber)?.stringValue
    else {
      Self.log.notice("render transform: no meetingEventId in props — passthrough")
      return props
    }

    guard
      let appGroupIdentifier = Self.appGroupIdentifier,
      let staged = UserDefaults(suiteName: appGroupIdentifier)?
        .dictionary(forKey: Self.stagingKeyPrefix + meetingEventId)
    else {
      Self.log.notice("render transform for meetingEventId=\(meetingEventId, privacy: .public) broadcastAt=\(broadcastAt, privacy: .public): nothing staged — passthrough")
      return props
    }

    // .debug: streamed (Console.app / idevicesyslog) but not persisted — this
    // fires on every render of every surface. The passthrough lines above stay
    // at .notice: an unenriched or id-less render is the anomaly worth keeping
    // in a retroactive `log collect`.
    Self.log.debug("render transform for meetingEventId=\(meetingEventId, privacy: .public) broadcastAt=\(broadcastAt, privacy: .public): merging \(staged.count, privacy: .public) staged keys")

    var merged = props
    for (key, value) in staged {
      merged[key] = value
    }
    return merged
  }
}
