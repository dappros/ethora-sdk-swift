<!-- @format -->

# Installation

## Distribution Options

Ethora Swift SDK supports three installation paths:

1. **Swift Package Manager (Xcode UI)**
2. **`Package.swift` dependency**
3. **Manual source copy** (enterprise/offline/vendor-policy fallback)

---

## Option 1: Add Package in Xcode

1. Open **File -> Add Package Dependencies...**
2. Enter repository URL:

```text
https://github.com/dappros/ethora-sdk-swift
```

3. Select products for your target:
- `XMPPChatCore`
- `XMPPChatUI`

---

## Option 2: Add dependency in Package.swift

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

---

## Option 3: Manual source copy

Use this option when your build environment cannot download dependencies from external Git hosts.

1. Copy folders from this repo into your app repository:
- `Sources/XMPPChatCore`
- `Sources/XMPPChatUI`

2. Add them as:
- local package targets (recommended), or
- direct project targets.

---

## XMPP Settings

```swift
let settings = XMPPSettings(
    devServer: "wss://your-xmpp-server.com:5443/ws",
    host: "your-xmpp-server.com",
    conference: "conference.your-xmpp-server.com",
    xmppPingOnSendEnabled: true
)
```

## Next Steps

- Check examples in `/Users/admin/Work/ethora-sdk-swift/Examples` to embed chat screens.
- For full integration flow, see `/Users/admin/Work/ethora-sdk-swift/README.md` and `/Users/admin/Work/ethora-sdk-swift/INTEGRATION.md`.
