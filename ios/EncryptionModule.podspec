require 'json'

package = JSON.parse(File.read(File.join(__dir__, '..', 'package.json')))

Pod::Spec.new do |s|
  s.name           = 'EncryptionModule'
  s.version        = package['version']
  s.summary        = package['description']
  s.license        = package['license']
  s.author         = package['author']
  s.homepage       = package['homepage']
  s.platform       = :ios, '13.4'
  s.source         = { git: package['repository'], tag: "v#{s.version}" }
  # NotificationService.swift is deliberately NOT in the pod — the config
  # plugin compiles it (plus its own copy of CryptoUtils.swift) directly into
  # the notification-service extension target. The LiveActivityEnrichment files
  # are main-app only: they run during the background wake an ActivityKit
  # push-to-start grants, which happens in the app process.
  # LiveActivityRenderEnrichment.swift is likewise excluded: the config plugin
  # compiles it into the expo-widgets WIDGET-EXTENSION target, where the render
  # pipeline discovers it by class name to re-apply staged enrichment that
  # broadcast-channel pushes would otherwise wipe.
  s.source_files   = 'EncryptionModule.swift', 'CryptoUtils.swift',
                     'LiveActivityEnrichment.swift', 'LiveActivityEnrichmentAppDelegateSubscriber.swift'
  s.dependency 'ExpoModulesCore'
  
  # Ensure we can use keychain
  s.frameworks     = 'Security'
  
  # Add keychain sharing entitlements
  s.pod_target_xcconfig = {
    'CODE_SIGN_ENTITLEMENTS' => 'EncryptionModule.entitlements',
    'OTHER_CODE_SIGN_FLAGS' => '--entitlements $(PODS_TARGET_SRCROOT)/EncryptionModule.entitlements'
  }
end