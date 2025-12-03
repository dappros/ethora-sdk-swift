<!-- @format -->

### XMPP Settings

```swift
let settings = XMPPSettings(
    devServer: "wss://your-xmpp-server.com:5443/ws",
    host: "your-xmpp-server.com",
    conference: "conference.your-xmpp-server.com",
    xmppPingOnSendEnabled: true
)
```

# Please check example folders to see how to add the Chat View into your app

## Add Swift Package Dependencies

1. In Xcode, go to **File → Add Packages...**
2. Click the **+** button at the bottom left
3. Select **Add Local...**
4. Navigate to: `/Users/admin/Work/native-cc/XMPPChatSwift`
5. Click **Add Package**

### Select Package Products

In the package selection dialog:

- ✅ Check **XMPPChatCore**
- ✅ Check **XMPPChatUI**
- Make sure they're added to your **ChatAppExample** target
- Click **Add Package**
