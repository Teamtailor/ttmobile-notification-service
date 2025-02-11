import Intents
import UserNotifications

class NotificationService: UNNotificationServiceExtension {
  var contentHandler: ((UNNotificationContent) -> Void)?
  var bestAttemptContent: UNMutableNotificationContent?

  override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
    self.contentHandler = contentHandler
    self.bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
    NSLog("didReceive")

    guard let bestAttemptContent = bestAttemptContent else {
      self.contentHandler?(request.content)
      return
    }

    guard let encryptedJson = bestAttemptContent.userInfo["encrypted_data"] as? String else {
      NSLog("No encrypted data, proceed as usual.")
      processNotificationContent(bestAttemptContent: bestAttemptContent, contentHandler: contentHandler)
      return
    }

    guard let encryptedData = parseJsonToMap(jsonString: encryptedJson) else {
      NSLog("Failed to parse encrypted data.")
      processNotificationContent(bestAttemptContent: bestAttemptContent, contentHandler: contentHandler)
      return
    }

    guard let encryptedKey = encryptedData["encrypted_key"] as? String,  // renamed from encrypted_key
          let cipherText = encryptedData["cipher_text"] as? String,
          let nonce = encryptedData["nonce"] as? String,
          let tag = encryptedData["tag"] as? String else {
      NSLog("Missing required encryption fields.")
      processNotificationContent(bestAttemptContent: bestAttemptContent, contentHandler: contentHandler)
      return
    }

    do {
      let decryptedJson = try CryptoUtils.hybridDecrypt(
        encryptedKey: encryptedKey,  // renamed parameter
        cipherText: cipherText,
        nonce: nonce,
        tag: tag
      )
      
      bestAttemptContent.userInfo["encrypted_data"] = nil

      if let decryptedData = parseJsonToMap(jsonString: decryptedJson) {
        mergeDecryptedData(decryptedData, into: bestAttemptContent)
      }
    } catch {
      NSLog("Decryption failed: \(error)")
    }

    processNotificationContent(bestAttemptContent: bestAttemptContent, contentHandler: contentHandler)
  }

  private func parseJsonToMap(jsonString: String) -> [String: Any]? {
    guard let data = jsonString.data(using: .utf8) else { return nil }
    do {
      let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
      if let dict = jsonObject as? [String: Any] {
        return dict
      } else {
        NSLog("Decrypted JSON is not a dictionary.")
        return nil
      }
    } catch {
      NSLog("JSON parsing error: \(error)")
      return nil
    }
  }

  private func processNotificationContent(bestAttemptContent: UNMutableNotificationContent, contentHandler: @escaping (UNNotificationContent) -> Void) {
    guard let body = bestAttemptContent.userInfo["body"] as? [AnyHashable: Any?],
          let sender = body["sender"] as? [AnyHashable: Any?],
          let id = sender["id"] as? String,
          let displayName = sender["displayName"] as? String,
          let avatarUrl = sender["avatarUrl"] as? String,
          let avatarUrlURL = URL(string: avatarUrl),
          let avatarImageData = try? Data(contentsOf: avatarUrlURL)
    else {
      NSLog("Missing required params for communication notification.")
      contentHandler(bestAttemptContent)
      return
    }

    let avatarImage = INImage(imageData: avatarImageData)

    let senderPerson = INPerson(
      personHandle: INPersonHandle(value: id, type: .unknown),
      nameComponents: PersonNameComponents(nickname: displayName),
      displayName: bestAttemptContent.title, // Display notification title as title
      image: avatarImage,
      contactIdentifier: nil,
      customIdentifier: nil,
      isMe: false, // Marks as sender
      suggestionType: .none
    )

    // Dummy person as recipient
    let selfPerson = INPerson(
      personHandle: INPersonHandle(value: "00000000-0000-0000-0000-000000000000", type: .unknown),
      nameComponents: nil,
      displayName: nil,
      image: nil,
      contactIdentifier: nil,
      customIdentifier: nil,
      isMe: true,
      suggestionType: .none
    )

    let incomingMessagingIntent = INSendMessageIntent(
      recipients: [selfPerson],
      outgoingMessageType: .outgoingMessageText,
      content: bestAttemptContent.body,
      speakableGroupName: nil,
      conversationIdentifier: bestAttemptContent.title, // Use title as conversation identifier
      serviceName: nil,
      sender: senderPerson,
      attachments: []
    )

    do {
      let updatedContent = try bestAttemptContent.updating(from: incomingMessagingIntent) as? UNMutableNotificationContent
      DispatchQueue.main.async {
        contentHandler(updatedContent ?? bestAttemptContent)
      }
    } catch {
      NSLog("Error updating notification with intent: \(error)")
      DispatchQueue.main.async {
        contentHandler(bestAttemptContent)
      }
    }
  }

  /// Merges decrypted data into the notification's userInfo.
  private func mergeDecryptedData(_ decryptedData: [String: Any], into bestAttemptContent: UNMutableNotificationContent) {
    if let title = decryptedData["title"] as? String {
      bestAttemptContent.title = title
    }

    if let message = decryptedData["message"] as? String {
      bestAttemptContent.body = message
    }

    // Update the title and body fields in the bestAttemptContent.userInfo["aps"]["alert"]
    // Not sure if this is necessary or makes a difference
    if var aps = bestAttemptContent.userInfo["aps"] as? [String: Any],
       var alert = aps["alert"] as? [String: Any] {
        if let title = decryptedData["title"] as? String {
            alert["title"] = title
        }
        if let message = decryptedData["message"] as? String {
            alert["body"] = message
        }
        aps["alert"] = alert
        bestAttemptContent.userInfo["aps"] = aps
    }

    let keysToMerge = ["body", "experienceId", "scopeKey"]
    for (key, value) in decryptedData {
      if keysToMerge.contains(key) {
          bestAttemptContent.userInfo[key] = value
      }
    }
  }

  override func serviceExtensionTimeWillExpire() {
    // If the extension times out, deliver the best attempt content
    DispatchQueue.main.async {
      self.contentHandler?(self.bestAttemptContent ?? UNNotificationContent())
    }
  }
}
