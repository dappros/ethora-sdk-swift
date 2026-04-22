# XMPPChatCore Integration Guide

This guide shows a production-safe integration of `XMPPChatCore` into **any Swift app** using placeholders only.

## 0. Replace These Placeholders First

Use your own values before testing:

- `<XMPP_USERNAME>`
- `<XMPP_PASSWORD>`
- `<ROOM_ID_OR_JID>`
- `<XMPP_WS_URL>`
- `<XMPP_HOST>`
- `<XMPP_CONFERENCE_DOMAIN>`
- Optional REST values (if you load rooms/users from API):
  - `<API_BASE_URL>`
  - `<JWT_TOKEN>`
  - `<APP_ID>`

Example room rule:
- If you only have room id (`<ROOM_ID_OR_JID>`), build full JID as:
  `\(<ROOM_ID_OR_JID>)@\(<XMPP_CONFERENCE_DOMAIN>)`

---

## 1. Add Package

In Xcode: **File → Add Package Dependencies**

```text
https://github.com/dappros/ethora-sdk-swift
```

Then import:

```swift
import XMPPChatCore
```

---

## 2. Configure XMPP Settings

```swift
let settings = XMPPSettings(
    devServer: "<XMPP_WS_URL>",
    host: "<XMPP_HOST>",
    conference: "<XMPP_CONFERENCE_DOMAIN>"
)
```

---

## 3. Create Client and Connect

```swift
let client = XMPPClient(
    username: "<XMPP_USERNAME>",
    password: "<XMPP_PASSWORD>",
    settings: settings
)

client.delegate = self
ClientRegistry.shared.setGlobalXMPPClient(client)
```

`XMPPClient` connects automatically and sends global presence after auth.

---

## 4. Wait Until Ready

```swift
while !client.isFullyConnected() {
    try? await Task.sleep(nanoseconds: 300_000_000)
}
```

---

## 5. Join Room(s) with Presence

```swift
func normalizedRoomJID(_ raw: String, conference: String) -> String {
    if raw.contains("@") { return raw }
    return "\(raw)@\(conference)"
}

let roomJID = normalizedRoomJID("<ROOM_ID_OR_JID>", conference: "<XMPP_CONFERENCE_DOMAIN>")
await client.sendPresenceToRoom(roomJID: roomJID)
```

For multiple rooms:

```swift
let roomJIDs: [String] = ["<ROOM_ID_OR_JID_1>", "<ROOM_ID_OR_JID_2>"].map {
    normalizedRoomJID($0, conference: "<XMPP_CONFERENCE_DOMAIN>")
}
await client.sendPresenceToAllRooms(roomJIDs: roomJIDs)
```

---

## 6. Send Text Message

Use `XMPPChatCore` operations object:

```swift
client.operations.sendTextMessage(
    roomJID: roomJID,
    firstName: "<SENDER_FIRST_NAME>",
    lastName: "<SENDER_LAST_NAME>",
    photo: "<SENDER_PHOTO_URL_OR_EMPTY>",
    walletAddress: "<SENDER_WALLET_OR_EMPTY>",
    userMessage: "Hello from iOS"
)
```

---

## 7. Load History (MAM)

```swift
client.operations.sendGetHistory(
    roomJID: roomJID,
    max: 20,
    before: ""
)
```

---

## 8. Implement Delegate (Messages + Raw Stanzas)

```swift
extension ChatManager: XMPPClientDelegate {
    func xmppClientDidConnect(_ client: XMPPClient) {
        print("Connected as \(client.username)")
    }

    func xmppClientDidDisconnect(_ client: XMPPClient) {
        print("Disconnected")
    }

    func xmppClient(_ client: XMPPClient, didReceiveMessage message: Message) {
        print("[MSG] room=\(message.roomJid) body=\(message.body)")
    }

    func xmppClient(_ client: XMPPClient, didReceiveStanza stanza: XMPPStanza) {
        print("[STANZA] name=\(stanza.name) attrs=\(stanza.attributes)")
    }

    func xmppClient(_ client: XMPPClient, didChangeStatus status: ConnectionStatus) {
        print("Status: \(status.rawValue)")
    }
}
```

---

## 9. Optional: JWT Login + Rooms API Flow

If your backend issues XMPP credentials via JWT:

```swift
let baseURL = URL(string: "<API_BASE_URL>")!
let loginResponse = try await AuthAPI.loginViaJwt(
    clientToken: "<JWT_TOKEN>",
    baseURL: baseURL
)

await MainActor.run {
    UserStore.shared.setUser(from: loginResponse)
}

let rooms = try await RoomsAPI.getRooms(
    baseURL: baseURL,
    appId: "<APP_ID>",
    conferenceDomain: "<XMPP_CONFERENCE_DOMAIN>"
)
```

Then create `XMPPClient` with `loginResponse.user.xmppUsername` and `loginResponse.user.xmppPassword`.

---

## 10. Disconnect

```swift
await client.disconnect()
```

Call this on logout only.

---

## Common Pitfalls

| Problem | Fix |
|---|---|
| `xmppStream` inaccessible | Do not use internal stream directly. Use `client.sendGlobalPresence()`, `client.sendPresenceToRoom()`, `client.operations.*`. |
| No incoming messages | Ensure room presence is sent before messaging/history. |
| Cannot send message | Confirm `client.isFullyConnected() == true` and room JID is full (`room@conference...`). |
| Wrong room JID format | Auto-append conference domain if `@` is missing. |
| Multiple duplicate connections | Keep a single `XMPPClient` per signed-in user session. |
