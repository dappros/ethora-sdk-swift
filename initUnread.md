# Headless Unread

How `ChatHeadlessSession` works internally and how to wire it into a host
app to drive a live unread badge **without mounting any chat UI**.

## How it works

`ChatHeadlessSession.shared.start(config:)` kicks off a Task that runs a
five-stage pipeline (see
`Sources/XMPPChatCore/Services/ChatHeadlessSession.swift`):

1. **`authenticating`** — if `UserStore` is empty, JWT autologin runs
   first (`config.jwtLogin.token` via `AuthAPI.loginViaJwt`), then falls
   back to `config.userLogin.user`. If neither is configured, the status
   transitions to `.failed`.
2. **`connecting`** — pulls `xmppPassword` from
   `UserStore.currentUser` and derives `xmppUsername` (in priority order:
   `xmppUsername` → wallet → email localpart). **If
   `ClientRegistry.shared.getGlobalXMPPClient()` already holds a client,
   it is reused — that is what guarantees no duplicate sockets.**
   Otherwise a new `XMPPClient(...)` is created and registered. The
   pipeline waits up to 15 seconds for `isFullyConnected()`.
3. **`syncingRooms`** — `RoomsAPI.getRooms` is called and each result
   goes into `RoomStore.shared.addRoomFromApi`. Then MUC presence is
   sent for every room in one batch via
   `client.sendPresenceToAllRooms(roomJIDs:)`. This step is critical:
   without it the server does not deliver broadcasts to this client and
   unread never moves.
4. `recomputeAllUnread` recomputes counters against the history that
   has already been hydrated (when `RoomStore.rooms[jid].messages` is
   empty it falls back to `MessageCache`).
5. Push: `PushNotificationManager.attachClient` plus
   `refreshRoomPushSubscriptions`. Finally `status = .ready`.

**From here, real-time updates run on their own**, without any further
involvement from the headless session. `XMPPClient.swift:948` calls
`RoomStore.shared.recomputeUnreadForRoom(...)` on every incoming
message stanza. `UnreadStateBridge`
(`Sources/XMPPChatCore/Hooks/UseUnreadStateBridge.swift:26`) is
subscribed to `RoomStore.$rooms` and recomputes
`totalUnreadCount` / `unreadByRoom` automatically on any change — the
host observes those updates over Combine.

**Coexistence with UI**: when `ChatWrapperView` is later mounted, its
view model (`UseChatWrapperInit.swift:235-244`) calls
`ClientRegistry.shared.getGlobalXMPPClient()` first, finds the same
socket the headless session is already holding, and skips creating a
new one. One `XMPPClient`, one set of subscriptions.

## Wiring it into a host app

### 1. Add the dependency

In Xcode: `File -> Add Package Dependencies...` and enter
`https://github.com/dappros/ethora-sdk-swift`. Link `XMPPChatCore` to
your target (you only need `XMPPChatUI` if you also render the chat
itself).

### 2. Start the session at app launch

Minimal example for a SwiftUI host whose user logs in via JWT:

```swift
import SwiftUI
import Combine
import XMPPChatCore

@main
struct MyApp: App {
    @StateObject private var unread = UnreadHost()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(unread)
                .onAppear { unread.startIfNeeded() }
        }
    }
}

@MainActor
final class UnreadHost: ObservableObject {
    @Published private(set) var total: Int = 0
    private let bridge = UnreadStateBridge()
    private var cancellables = Set<AnyCancellable>()

    init() {
        bridge.$totalUnreadCount
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.total = $0 }
            .store(in: &cancellables)
    }

    func startIfNeeded() {
        var config = ChatConfig()
        config.baseUrl = "https://api.chat.ethora.com/v1"
        config.appId = "YOUR_APP_ID"
        config.customAppToken = "YOUR_APP_TOKEN"
        config.xmppSettings = XMPPSettings(
            xmppServerUrl: "wss://xmpp.chat.ethora.com/ws",
            host: "xmpp.chat.ethora.com",
            conference: "conference.xmpp.chat.ethora.com"
        )
        config.jwtLogin = JWTLoginConfig(token: "YOUR_CLIENT_JWT", enabled: true)

        ChatHeadlessSession.shared.start(config: config)
    }

    func logout() async {
        await ChatHeadlessSession.shared.stop()
    }
}
```

### 3. Bind to a badge

```swift
struct RootTabBar: View {
    @EnvironmentObject var unread: UnreadHost

    var body: some View {
        TabView {
            ChatTab()
                .tabItem { Label("Chat", systemImage: "message") }
                .badge(unread.total)         // tab-bar badge
            // ...
        }
    }
}
```

For the app icon badge use either
`bridge.bindBadge { count in UIApplication.shared.applicationIconBadgeNumber = count }`
or a plain Combine subscription on `bridge.$totalUnreadCount`.

### 4. If you authenticate your own way (not JWT)

Authenticate first via `AuthAPI.loginWithEmail(...)` plus
`UserStore.shared.setUser(from:)`, **then** call
`ChatHeadlessSession.shared.start(config:)`. The headless session sees
the existing user and skips its own auth step.

### 5. When you later want to show the chat

Mount `ChatWrapperView(config:initialRoomJID:onUnreadCountChanged:)`
the usual way. It picks up the live client and does not churn the
socket. No changes are required on the UI side.

## Things to keep in mind

- **One process — one session.** `ChatHeadlessSession.shared` and
  `ClientRegistry.shared` are singletons; this design does not fit a
  widget or notification-service extension, which need their own
  connection.
- **`stop()` tears down the socket.** Do not call it while
  `ChatWrapperView` is on screen. The typical place to call it is
  logout.
- **Auth must yield `xmppPassword`.** If the backend returns a user
  without `xmppPassword`, the pipeline halts at
  `.failed("Missing XMPP credentials on user")`.
- **Battery footprint.** The session keeps a WebSocket open while the
  app is active; iOS suspends the socket on its own when the app goes
  to background, and `SessionRecoveryManager` brings it back on
  foreground.
- **Observe `$status`** if you want a loading indicator or want to
  surface errors — it is a `@Published` enum.
