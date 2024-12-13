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
  s.source_files   = 'EncryptionModule.swift', 'CryptoUtils.swift'
  s.dependency 'ExpoModulesCore'
  
  # Ensure we can use keychain
  s.frameworks     = 'Security'
  
  # Add keychain sharing entitlements
  s.pod_target_xcconfig = {
    'CODE_SIGN_ENTITLEMENTS' => 'EncryptionModule.entitlements',
    'OTHER_CODE_SIGN_FLAGS' => '--entitlements $(PODS_TARGET_SRCROOT)/EncryptionModule.entitlements'
  }
end