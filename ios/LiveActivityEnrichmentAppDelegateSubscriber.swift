import ExpoModulesCore

/// Starts the Live Activity enrichment observer on EVERY launch — crucially
/// including background launches triggered by an ActivityKit push-to-start
/// notification, where no JS may ever run. An app-delegate subscriber is the
/// earliest JS-independent native hook Expo offers (module OnCreate only runs
/// once JS instantiates the module).
public class LiveActivityEnrichmentAppDelegateSubscriber: ExpoAppDelegateSubscriber {
  public func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    if #available(iOS 16.2, *) {
      Task { await LiveActivityEnricher.shared.start() }
    }
    return true
  }
}
