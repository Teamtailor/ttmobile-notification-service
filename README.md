# Teamtailor Notification Service

This is a notification service that modifies incoming notifications.

Currently it support communication notifications for ios. Adding company logo as avatar.

It also supports e2e encryption for notifications.

# Installation in managed Expo projects

Just add ttmobile-notification-service as a config plugin in your app.json. Then send payload to apns like this:

```
sender: {
  id,
  avatarUrl,
  displayName
}
```

# End-to-End Encrypted Push Notifications System

## Overview
The system implements end-to-end encryption for push notifications across iOS and Android platforms using a hybrid encryption scheme combining RSA and AES.

## Key Components

### Key Management
- Each device generates 2048-bit RSA key pair during initialization
- Private keys stored securely in platform keychain/keystore
- Public keys transmitted to server and stored with device tokens
- Keys are accessible only after first device unlock (iOS) or with similar Android restrictions

### Encryption Process (Server)
1. Prepares notification payload with title, message and data 
2. Generates random AES-256 key and IV for GCM encryption
3. Encrypts payload using AES-GCM producing ciphertext and auth tag
4. Encrypts AES key with device's public RSA key (OAEP-SHA1 padding)
5. Packages encrypted components into notification:
   - Encrypted AES key
   - Ciphertext
   - Nonce (IV)
   - Authentication tag

### Push Delivery
- Server sends encrypted package through APNS/FCM
- Includes fallback message for legacy app versions
- Handles token invalidation and cleanup

### Decryption Process (Client)
1. Device receives notification in background service
2. Retrieves private RSA key from secure storage
3. Decrypts AES key using RSA private key
4. Uses AES key to verify and decrypt payload  
5. Updates notification content with decrypted data

### Security Features
- Industry standard algorithms (RSA-2048, AES-256-GCM)
- Keys never leave secure hardware
- Per-notification unique encryption keys
- Authenticated encryption prevents tampering
- Graceful fallback for pre-unlock state and legacy versions

## Implementation Notes
- Uses platform-specific secure storage (Keychain/Keystore) with appropriate access controls
- Implements OAEP padding for RSA for enhanced security
- Handles key rotation and device token management
- Provides consistent cross-platform behavior
- Includes error handling and logging
## Live Activity Enrichment (iOS)

An ActivityKit push-to-start notification wakes the app in the background "to
download assets that the Live Activity needs" (Apple). During that wake,
`LiveActivityEnricher` (started by `LiveActivityEnrichmentAppDelegateSubscriber`
on every launch, with no JS dependency) enriches push-started Live Activities
with E2E-encrypted PII entirely natively:

1. Observes `Activity<LiveActivityAttributes>.activities` + `.activityUpdates`.
   The attributes struct is a shape-identical duplicate of expo-widgets'
   internal one — ActivityKit matches activities by unqualified type name, the
   same string the push payload carries in `attributes-type`.
2. Reads the content-state `props` JSON and extracts `encrypted_data` — a
   `MobileNotifications::PayloadEncryptor` blob
   `{encrypted_key, cipher_text, nonce, tag}` (object or JSON string),
   encrypted against this device's registered public key.
3. Decrypts via `CryptoUtils.hybridDecrypt` into a JSON object of PII fields,
   e.g. `{"candidateName": "...", "avatarUrl": "https://..."}`.
4. Downloads `avatarUrl` into `<app group>/ExpoWidgets/la-avatar-<key>` (the
   directory expo-widgets shares with the widget extension) and rewrites the
   field to the local `file://` URL. `<key>` = `props.meetingEventId`.
5. Stages the enrichment in app-group `UserDefaults` under
   `__tt_la_enrichment_<key>` — the widget extension merges it into props at
   render time, so a later APNs channel update that replaces the content-state
   cannot permanently wipe the enrichment (those updates don't wake the app).
6. Updates the activity with the enriched props merged in (preserving
   `staleDate`/`relevanceScore`) to re-render immediately.

The decryption key is `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: a
wake between reboot and first unlock leaves the activity un-enriched (the
widget falls back to its non-PII layout) and the next launch retries.

Debug: `log collect --device`, subsystem = app bundle id, category `LA-enrich`.
