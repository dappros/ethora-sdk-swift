# Ethora Chat Component (Swift)

This SDK gives you a ready-to-use chat UI + chat core for Swift (SwiftUI, SPM).

Part of the [Ethora SDK ecosystem](https://github.com/dappros/ethora#ecosystem) — see all SDKs, tools, and sample apps. Follow cross-SDK updates in the [Release Notes](https://github.com/dappros/ethora/blob/main/RELEASE-NOTES.md).

## Install Option 1: Swift Package Manager (Xcode)

### 1. Add package

In Xcode:

1. File -> Add Package Dependencies...
2. Enter repository URL:

```text
https://github.com/dappros/ethora-sdk-swift
```

3. Add products to your app target:
- `XMPPChatCore`
- `XMPPChatUI`

### 2. Import modules

```swift
import XMPPChatCore
import XMPPChatUI
```

## Install Option 2: Package.swift dependency

```swift
// Package.swift
.dependencies([
    .package(url: "https://github.com/dappros/ethora-sdk-swift", branch: "main")
]),
.targets([
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "XMPPChatCore", package: "ethora-sdk-swift"),
            .product(name: "XMPPChatUI", package: "ethora-sdk-swift")
        ]
    )
])
```

## Install Option 3: Manual Source Copy

Use this when your org cannot fetch remote packages at build time (enterprise/offline/vendor-policy constraints).

### 1. Copy folders into your project

Copy these folders from this repository:

- `Sources/XMPPChatCore`
- `Sources/XMPPChatUI`

### 2. Add as local package or local targets

Recommended: create a local Swift package in your app workspace and point it to copied sources.

## Install Option Selection

- Use **Option 1 (Xcode SPM)** for most app teams.
- Use **Option 2 (`Package.swift`)** for package-first or multi-module repositories.
- Use **Option 3 (manual copy)** for controlled distribution environments.

## SDK Playground (in-repo example app)

For manual testing of API + XMPP + `ChatWrapperView` without a separate host app, use **`Examples/SDKPlayground`**: Tab bar (**Setup** / **Chat** / **Logs**), local package path `../..`. See [Examples/SDKPlayground/README.md](Examples/SDKPlayground/README.md).

## Chat Configuration

Reliable integration flow in Swift is:

1. Build `ChatConfig`
2. Apply config with `ConfigStore.shared.mergeConfig(...)` (or `updateConfig(...)`)
3. Render `ChatWrapperView(config:initialRoomJID:onUnreadCountChanged:)`

```swift
import SwiftUI
import XMPPChatCore
import XMPPChatUI

struct EthoraChatScreen: View {
    private let singleRoomJid = "699c6923429c2757ac8ab6a4_playground-room-1"

    private var appConfig: ChatConfig {
        var config = ChatConfig()
        config.appId = BuildConfig.APP_ID
        config.baseUrl = BuildConfig.API_BASE_URL
        config.customAppToken = BuildConfig.API_TOKEN
        config.disableRooms = true
        config.defaultLogin = false

        config.chatHeaderSettings = ChatHeaderSettingsConfig(
            roomTitleOverrides: [singleRoomJid: "Playground Room 1"],
            chatInfoButtonDisabled: true,
            backButtonDisabled: true
        )

        config.xmppSettings = XMPPSettings(
            xmppServerUrl: BuildConfig.XMPP_DEV_SERVER,
            host: BuildConfig.XMPP_HOST,
            conference: BuildConfig.XMPP_CONFERENCE
        )

        if !BuildConfig.USER_TOKEN.isEmpty {
            config.jwtLogin = JWTLoginConfig(
                token: BuildConfig.USER_TOKEN,
                enabled: true
            )
        }

        return config
    }

    var body: some View {
        ChatWrapperView(
            config: appConfig,
            initialRoomJID: singleRoomJid,
            onUnreadCountChanged: { totalUnread in
                // use this to update your external tab bar badge
                print("Unread count: \(totalUnread)")
            }
        )
        .onAppear {
            ConfigStore.shared.mergeConfig(appConfig)
        }
    }
}
```

### Config notes

- `disableRooms = true` + `initialRoomJID` gives single-room mode behavior.
- `jwtLogin` is used when `enabled = true` and token is provided.
- `chatHeaderSettings.roomTitleOverrides` lets you replace raw JID in header.
- `customAppToken`, `baseUrl`, `appId`, `xmppSettings` are consumed by API/XMPP flows.

## Authentication Options

### Option A: JWT login via config

```swift
var config = ChatConfig()
config.jwtLogin = JWTLoginConfig(token: "YOUR_JWT", enabled: true)
ConfigStore.shared.updateConfig(config)
```

`ChatWrapperView` will run JWT autologin automatically when this is enabled.

### Option B: Email/password login

```swift
let response = try await AuthAPI.loginWithEmail(
    email: email,
    password: password
)
await UserStore.shared.setUser(from: response)
```

## Host App Unread Hook (drop-in)

Use these iOS drop-in patterns to propagate unread values into app-level badges:

### Pattern A: wrapper callback (immediate badge propagation)

```swift
ChatWrapperView(
    config: appConfig,
    initialRoomJID: singleRoomJid,
    onUnreadCountChanged: { totalUnread in
        appBadgeStore.setChatUnread(totalUnread)
    }
)
```

### Pattern B: reactive store binding (global app-shell badge)

```swift
import SwiftUI
import XMPPChatCore

struct ChatTabBadge: View {
    @ObservedObject private var roomStore = RoomStore.shared

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "message")
            if roomStore.totalUnreadCount > 0 {
                Text(displayCount(roomStore.totalUnreadCount, maxCount: 99))
                    .font(.caption2)
                    .padding(4)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .offset(x: 10, y: -8)
            }
        }
    }

    private func displayCount(_ count: Int, maxCount: Int) -> String {
        count > maxCount ? "\(maxCount)+" : "\(count)"
    }
}
```

Important behavior:

- Unread values become meaningful after chat initialization and room loading.
- If chat is not initialized yet, count is `0`.

## Persistence

- `ConfigStore` persists codable config fields in `UserDefaults`.
- `UserStore` persists user/token/refresh-token in `UserDefaults`.
- `RoomStore` tracks total unread state for badge integration.

## Build / Validate

```bash
xcodebuild -scheme XMPPChatSwift-Package -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Optional package resolution check:

```bash
swift package resolve
```
