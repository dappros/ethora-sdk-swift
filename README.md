# Ethora SDK for Swift (`ethora-sdk-swift`)

Production-ready iOS chat SDK with:
- `XMPPChatCore` for auth, API, XMPP transport, stores, and messaging operations
- `XMPPChatUI` for ready-made SwiftUI chat UI on top of the core

This repository ships as a Swift Package with both products.

## Table of Contents

1. [What You Get](#what-you-get)
2. [Requirements](#requirements)
3. [Installation](#installation)
4. [Quick Start (Recommended)](#quick-start-recommended)
5. [Authentication Flows](#authentication-flows)
6. [Using `XMPPChatCore` Without UI](#using-xmppchatcore-without-ui)
7. [Configuration Reference (`ChatConfig`)](#configuration-reference-chatconfig)
8. [Core API Reference](#core-api-reference)
9. [Push Notifications (FCM)](#push-notifications-fcm)
10. [Persistence and Stores](#persistence-and-stores)
11. [Examples in This Repo](#examples-in-this-repo)
12. [Production Notes and Pitfalls](#production-notes-and-pitfalls)
13. [Build and Validation](#build-and-validation)

## What You Get

### `XMPPChatCore`

- XMPP over WebSocket (`Starscream`)
- Connection lifecycle and reconnect logic
- Presence handling (global + per-room)
- Message operations: text, media metadata, reactions, edit, delete, typing, history (MAM)
- REST APIs:
  - auth (`loginWithEmail`, `loginViaJwt`, token refresh)
  - rooms (fetch/create/private/create member actions/report/delete)
  - file upload
  - push registration
- Global stores (`ConfigStore`, `UserStore`, `RoomStore`)
- Push subscription orchestration for backend + room-level subscriptions

### `XMPPChatUI`

- Drop-in `ChatWrapperView`
- Room list and single-room mode
- Chat room screen with message list, media rendering, typing indicator, status views
- Modals for profile/settings/report/member actions
- Empty/loading/error states and retry surfaces
- Unread count callback for host-app badge sync

## Requirements

- iOS 15+
- Swift tools 5.9+
- Xcode with Swift Package Manager support

## Installation

### Option 1: Xcode UI (most common)

1. `File` -> `Add Package Dependencies...`
2. Enter:

```text
https://github.com/dappros/ethora-sdk-swift
```

3. Add products to your app target:
- `XMPPChatCore`
- `XMPPChatUI`

### Option 2: `Package.swift`

```swift
// Package.swift
.dependencies([
    .package(url: "https://github.com/dappros/ethora-sdk-swift", branch: "main")
]),
.targets([
    .target(
        name: "YourAppTarget",
        dependencies: [
            .product(name: "XMPPChatCore", package: "ethora-sdk-swift"),
            .product(name: "XMPPChatUI", package: "ethora-sdk-swift")
        ]
    )
])
```

### Option 3: Manual source copy (enterprise/offline)

Copy:
- `Sources/XMPPChatCore`
- `Sources/XMPPChatUI`

If you do this, ensure dependency parity for core transport (`Starscream`).

## Quick Start (Recommended)

This path is fastest for production embedding.

### 1. Import modules

```swift
import SwiftUI
import XMPPChatCore
import XMPPChatUI
```

### 2. Build config

```swift
private func makeChatConfig() -> ChatConfig {
    var config = ChatConfig()

    // API/XMPP
    config.baseUrl = "https://api.chat.ethora.com/v1"
    config.appId = "YOUR_APP_ID"
    config.customAppToken = "YOUR_ETHORA_APP_TOKEN"
    config.xmppSettings = XMPPSettings(
        xmppServerUrl: "wss://xmpp.chat.ethora.com:5443/ws",
        host: "xmpp.chat.ethora.com",
        conference: "conference.xmpp.chat.ethora.com"
    )

    // Auth (JWT autologin via /users/client)
    config.jwtLogin = JWTLoginConfig(token: "YOUR_CLIENT_JWT", enabled: true)

    // Optional: single-room mode
    config.disableRooms = true

    return config
}
```

### 3. Render chat

```swift
struct ChatScreen: View {
    private let roomJID = "my-room@conference.xmpp.chat.ethora.com"

    var body: some View {
        let config = makeChatConfig()

        ChatWrapperView(
            config: config,
            initialRoomJID: roomJID,
            onUnreadCountChanged: { totalUnread in
                // Sync tab badge / app badge
                print("Unread: \(totalUnread)")
            }
        )
        .onAppear {
            // Keep global config synced for other stores/components
            ConfigStore.shared.mergeConfig(config)
        }
    }
}
```

## Authentication Flows

### A) JWT login (recommended for host apps)

- Set `config.jwtLogin = JWTLoginConfig(token: ..., enabled: true)`
- `ChatWrapperViewModel` performs autologin through `AuthAPI.loginViaJwt(clientToken:)`

### B) Email/password

```swift
let response = try await AuthAPI.loginWithEmail(
    email: email,
    password: password,
    baseURL: URL(string: "https://api.chat.ethora.com/v1")!,
    appToken: "YOUR_ETHORA_APP_TOKEN"
)
await UserStore.shared.setUser(from: response)
```

### C) Preloaded user

```swift
var config = ChatConfig()
config.userLogin = UserLoginConfig(enabled: true, user: preAuthenticatedUser)
```

## Headless Unread (no chat UI mounted)

Use this when the host app needs a live unread badge while the chat
screen is closed — equivalent to a `useChatHeadless()` + `useUnreadCount()`
pair in React.

```swift
import XMPPChatCore

@MainActor
final class UnreadHost: ObservableObject {
    @Published private(set) var totalUnread: Int = 0

    private let bridge = UnreadStateBridge()
    private var cancellable: AnyCancellable?

    init() {
        cancellable = bridge.$totalUnreadCount
            .receive(on: RunLoop.main)
            .assign(to: \.totalUnread, on: self)
    }

    func startSession(config: ChatConfig) {
        ChatHeadlessSession.shared.start(config: config)
    }

    func stopSession() async {
        await ChatHeadlessSession.shared.stop()
    }
}
```

`ChatHeadlessSession.shared.start(config:)` runs the same auth → XMPP →
rooms-sync → MUC presence → unread recompute pipeline that
`ChatWrapperView` does internally, but without rendering anything. The
created `XMPPClient` is registered with `ClientRegistry`, so a later
`ChatWrapperView` mount reuses the same socket — no duplicate
presences/subscriptions.

Call `stop()` on logout. Do not call it while `ChatWrapperView` is on
screen.

## Using `XMPPChatCore` Without UI

Use this when you need a custom UI while reusing transport + operations.

```swift
import XMPPChatCore

let settings = XMPPSettings(
    xmppServerUrl: "wss://xmpp.chat.ethora.com:5443/ws",
    host: "xmpp.chat.ethora.com",
    conference: "conference.xmpp.chat.ethora.com"
)

let client = XMPPClient(
    username: "user@xmpp.chat.ethora.com",
    password: "xmppPassword",
    settings: settings
)

client.delegate = self

// Wait until fully connected if needed
while !client.isFullyConnected() {
    try? await Task.sleep(nanoseconds: 300_000_000)
}

await client.sendPresenceToRoom(roomJID: "room@conference.xmpp.chat.ethora.com")

client.operations.sendTextMessage(
    roomJID: "room@conference.xmpp.chat.ethora.com",
    firstName: "John",
    lastName: "Doe",
    photo: "",
    walletAddress: "",
    userMessage: "Hello"
)

client.operations.sendGetHistory(
    chatJID: "room@conference.xmpp.chat.ethora.com",
    max: 20,
    before: nil
)
```

## Configuration Reference (`ChatConfig`)

`ChatConfig` has many options. Key groups below.

### Core connectivity

- `baseUrl`: REST base URL
- `appId`: app id used in room/push requests
- `customAppToken`: app token for app-scoped auth requests
- `xmppSettings`: `XMPPSettings` (WebSocket URL, host, conference)

`XMPPSettings` fields:
- `xmppServerUrl`: preferred server URL key
- `devServer`: legacy alias, kept for compatibility
- `host`
- `conference`
- `xmppPingOnSendEnabled`

### Login/auth config

- `googleLogin: GoogleLoginConfig`
- `jwtLogin: JWTLoginConfig`
- `userLogin: UserLoginConfig`
- `customLogin: CustomLoginConfig`
- `refreshTokens: RefreshTokensConfig`

### UI/UX toggles

- `disableHeader`, `disableMedia`, `disableRooms`
- `disableInteractions`, `disableRoomMenu`, `disableRoomConfig`, `disableNewChatButton`
- `disableProfilesInteractions`, `disableUserCount`, `disableTypingIndicator`
- `disableChatInfo: DisableChatInfoConfig`
- `chatHeaderSettings: ChatHeaderSettingsConfig`
- `enableRoomsRetry: EnableRoomsRetryConfig`

### Styling

- `colors: ChatColors` (`primary`, `secondary`)
- `backgroundChat: BackgroundChatConfig`
- `bubleMessage: MessageBubbleStyle`
- `roomListStyles`, `chatRoomStyles` (dynamic dictionaries)
- `headerLogo`

### Message pipeline and behavior hooks

- `messageTextFilter: MessageTextFilterConfig`
- `secondarySendButton: SecondarySendButtonConfig`
- `customTypingIndicator: CustomTypingIndicatorConfig`
- `blockMessageSendingWhenProcessing: BlockMessageSendingConfig`
- `eventHandlers: ChatEventHandlers`
- `messageNotifications: MessageNotificationConfig`
- `customComponents: CustomComponentsProtocol`

### Rooms and data behavior

- `defaultRooms`, `customRooms`
- `forceSetRoom`, `setRoomJidInPath`, `chatHeaderBurgerMenu`
- `clearStoreBeforeInit`, `disableSentLogic`, `initBeforeLoad`, `newArch`
- `botMessageAutoScroll`
- `whitelistSystemMessage`
- `translates: TranslationsConfig`
- `push: PushNotificationConfig`

### Important persistence detail

`ConfigStore` persists only codable fields. Closure- and `AnyView`-based options are runtime-only and are not serialized.

## Core API Reference

### Auth

- `AuthAPI.loginWithEmail(email:password:baseURL:appToken:useEthoraJwtWordPrefix:)`
- `AuthAPI.loginViaJwt(clientToken:baseURL:)`
- `AuthAPI.refreshToken(refreshToken:baseURL:appToken:)`
- `AuthAPI.checkEmailExist(email:baseURL:appToken:)`
- `AuthAPI.uploadFile(fileData:fileName:mimeType:baseURL:token:)`

### Rooms

- `RoomsAPI.getRooms(baseURL:appId:conferenceDomain:)`
- `RoomsAPI.postRoom(...)`
- `RoomsAPI.postPrivateRoom(...)`
- `RoomsAPI.getRoomByName(...)`
- `RoomsAPI.postAddRoomMember(...)`
- `RoomsAPI.deleteRoomMember(...)`
- `RoomsAPI.postReportRoom(...)`
- `RoomsAPI.postReportMessage(...)`
- `RoomsAPI.deleteRoom(...)`

### XMPP client

- `XMPPClient.checkOnline()`
- `XMPPClient.checkConnecting()`
- `XMPPClient.isFullyConnected()`
- `XMPPClient.ensureConnected(timeout:)`
- `XMPPClient.sendGlobalPresence()`
- `XMPPClient.sendPresenceToRoom(roomJID:)`
- `XMPPClient.joinRoomsAndWait(roomJIDs:timeout:)`
- `XMPPClient.disconnect()`

### Message operations (`client.operations`)

- `sendTextMessage(...)`
- `sendMediaMessage(...)`
- `sendGetHistory(chatJID:max:before:otherId:)`
- `editMessage(chatId:messageId:text:)`
- `deleteMessage(room:msgId:)`
- `sendMessageReaction(...)`
- `sendTypingRequest(chatId:fullName:start:)`

## Push Notifications (FCM)

The SDK supports:
- backend push token registration (`PushAPI`)
- room-level push subscriptions (`PushSubscriptionService`)

Typical sequence:

1. Complete auth (`UserStore` must have user token)
2. Attach live XMPP client
3. Provide/update FCM token

```swift
PushNotificationManager.shared.attachClient(client)
PushNotificationManager.shared.updateFCMToken(fcmToken)
```

Optional config:

```swift
config.push = PushNotificationConfig(
    enabled: true,
    appId: "YOUR_APP_ID",
    pushBaseURL: "https://api.chat.ethora.com/v1"
)
```

## Persistence and Stores

### `UserStore`

- Holds current user, token, refresh token, auth state
- Persists under `UserDefaults`
- Call `clearUser()` on logout

### `RoomStore`

- Holds room dictionary, active room, unread data, edit state
- Persists room data in cache
- Message cache is bounded (keeps recent messages per room)

### `ConfigStore`

- Global chat config singleton
- `mergeConfig(_:)` for partial updates
- `updateConfig(_:)` for full replacement
- Persists codable part of config

## Examples in This Repo

- `Examples/ChatAppExample` – app integration example
- `Examples/XMPPChatCoreMockiOSApp` – core-focused demo
- `Examples/SDKPlayground` – interactive playground with setup/chat/log tabs

Also see:
- `INSTALLATION.md`
- `INTEGRATION.md`
- `features.md`

## Production Notes and Pitfalls

- Do not rely on bundled dev defaults from `AppConfig` in production.
- `ConfigStore` initialization applies Ethora dev defaults; always merge/update your own `baseUrl`, `appId`, and `xmppSettings` before presenting chat.
- Ensure your auth flow provides `xmppUsername`/`xmppPassword` before showing chat.
- `ChatWrapperView` shows a blocking auth message when user credentials are missing.
- For single-room mode, use full room JID: `room@conference.domain`.
- `RoomsAPI` requires user auth in `UserStore`; call login first.
- Non-codable config entries (closures/custom views) must be reapplied each app launch.

## Build and Validation

```bash
xcodebuild -scheme XMPPChatSwift-Package -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Optional package resolution check:

```bash
swift package resolve
```
