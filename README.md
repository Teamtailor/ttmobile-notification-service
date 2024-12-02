# ttmobile-notification-service

This is a notification service that modifies incoming notifications.

Currently it support communication notifications for ios. Adding company logo as avatar.

It also supports e2e encryption for notifications-

# Installation in managed Expo projects

Just add ttmobile-notification-service as a config plugin in your app.json. Then send payload to apns like this:

```
sender: {
  id,
  avatarUrl,
  displayName
}
```

