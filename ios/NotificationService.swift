import UserNotifications
import Intents

class NotificationService: UNNotificationServiceExtension {
  var contentHandler: ((UNNotificationContent) -> Void)?
  var bestAttemptContent: UNMutableNotificationContent?

  override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
    self.contentHandler = contentHandler
    self.bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

    guard let body = self.bestAttemptContent?.userInfo["body"] as? [AnyHashable: Any?],
          let sender = body["sender"] as? [AnyHashable: Any?],
          let id = sender["id"] as? String,
          let displayName = sender["displayName"] as? String,
          let avatarUrl = sender["avatarUrl"] as? String,
          let avatarUrlURL = URL(string: avatarUrl),
          let avatarImageData: Data = try? Data(contentsOf: avatarUrlURL) else {
      contentHandler(self.bestAttemptContent!)
      return
    }
    
    let avatarImage: INImage = INImage(imageData: avatarImageData)

    let senderPerson = INPerson(
      personHandle: INPersonHandle(value: id, type: INPersonHandleType.unknown),
      nameComponents: PersonNameComponents.init(nickname: displayName),
      displayName: self.bestAttemptContent?.title, // we want to display the notification title as title
      image: avatarImage,
      contactIdentifier: nil,
      customIdentifier: nil,
      isMe: false, // this makes the OS recognize this as a sender
      suggestionType: INPersonSuggestionType.none
    )

    // this is just a dummy person that will be used as the recipient
    let selfPerson = INPerson(
      personHandle: INPersonHandle(value: "00000000-0000-0000-0000-000000000000", type: INPersonHandleType.unknown),
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
      outgoingMessageType: INOutgoingMessageType.outgoingMessageText, // This marks the message as outgoing
      content: self.bestAttemptContent?.body,
      speakableGroupName: nil, // INSpeakableString(spokenPhrase: content.title),
      conversationIdentifier: self.bestAttemptContent?.title, // we want to display the notification title as title
      serviceName: nil,
      sender: senderPerson, // this marks the message sender as the person we defined above
      attachments: []
    )

    do {
      self.bestAttemptContent = try self.bestAttemptContent!.updating(from: incomingMessagingIntent) as? UNMutableNotificationContent
      contentHandler(self.bestAttemptContent!)
    } catch let error {
        print("error \(error)")
    }
  }
    
  override func serviceExtensionTimeWillExpire() {
    // If request takes to long, this will be executed to deliver the notification
    if let contentHandler = self.contentHandler, let bestAttemptContent = self.bestAttemptContent {
      contentHandler(bestAttemptContent)
    }
  }
}
