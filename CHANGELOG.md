# Changelog

All notable changes to this package are documented here. For cross-SDK release notes, see [ethora/RELEASE-NOTES.md](https://github.com/dappros/ethora/blob/main/RELEASE-NOTES.md).

---

## [26.04.22]

- **Refactored:** API surface alignment — `AppConfig.swift`, `AuthAPI.swift`, `RoomsAPI+Actions.swift`, `RoomsAPI+Rooms.swift`, `XMPPClient.swift`, `MessageParser.swift`, `ChatRoomViewModel.swift`, `RoomListView.swift` signatures renamed for consistency ([`146c52f`](https://github.com/dappros/ethora-sdk-swift/commit/146c52f))
- **New:** `Sources/XMPPChatApp/main.swift` entry point ([`146c52f`](https://github.com/dappros/ethora-sdk-swift/commit/146c52f))
- **Refactored:** `Examples/` folder removed from SDK repo — sample/playground moving to a dedicated repo ([`97d54f9`](https://github.com/dappros/ethora-sdk-swift/commit/97d54f9))

## [26.04.21]

- **New:** `UnreadStateBridge` hook for badge propagation to host apps ([`83208b9`](https://github.com/dappros/ethora-sdk-swift/commit/83208b9))
- **Testing:** Added `UnreadStateBridgeTests` (90 lines) ([`83208b9`](https://github.com/dappros/ethora-sdk-swift/commit/83208b9))
- **Docs:** Overhauled README + `INSTALLATION.md`; new `features.md` summarising SDK capabilities ([`0e1605f`](https://github.com/dappros/ethora-sdk-swift/commit/0e1605f))

## [26.04.13]

- **Improved:** `MessageLoaderQueue` reliability update + `RoomListView` tweak ([`0150fb2`](https://github.com/dappros/ethora-sdk-swift/commit/0150fb2))

## [26.04.06]

- **New:** SDK playground (`Examples/SDKPlayground/`) — Setup / Chat / Logs tabs for exercising SDK features ([`53a8839`](https://github.com/dappros/ethora-sdk-swift/commit/53a8839), [`c4ac7d0`](https://github.com/dappros/ethora-sdk-swift/commit/c4ac7d0))
- **New:** Single-chat mode via `ChatWrapperView` + `UseChatWrapperInit` hook ([`7122809`](https://github.com/dappros/ethora-sdk-swift/commit/7122809))
- **Fixed:** Playground setup tweaks ([`257fdc7`](https://github.com/dappros/ethora-sdk-swift/commit/257fdc7))

## [26.03.30 – 26.04.03]

Push notifications rewrite ([`0b44384`](https://github.com/dappros/ethora-sdk-swift/commit/0b44384)):

- **New:** `PushNotificationManager.swift`, `PushSubscriptionService.swift`, `PendingNotificationJidStore.swift`
- **New:** `WalletUsername.swift` utility
- **New:** `AppDelegate.swift` + `GoogleService-Info.plist` in `ChatAppExample`
- **Refactored:** `XMPPClient+Connection/Handlers/Pings/Stream.swift` partials consolidated into a single `XMPPClient.swift`
- **Refactored:** `ChatRoomViewModel+Actions/History/Messages/Observers/XMPP.swift` collapsed into `ChatRoomViewModel.swift`
- **Improved:** `PushAPI` + `AuthAPI` + `ConfigStore` updated for new push flow

## [26.03.26]

- **New:** `sendGlobalPresence` operation in `XMPPClient+Operations` ([`d15067b`](https://github.com/dappros/ethora-sdk-swift/commit/d15067b))
- **Fixed:** Nickname handling in XMPP ([`16eacdf`](https://github.com/dappros/ethora-sdk-swift/commit/16eacdf))
- **Improved:** Extra debug logging ([`8954496`](https://github.com/dappros/ethora-sdk-swift/commit/8954496), [`30f99c8`](https://github.com/dappros/ethora-sdk-swift/commit/30f99c8))
- **Docs:** Documentation and example app updates ([`a874a22`](https://github.com/dappros/ethora-sdk-swift/commit/a874a22))

## [26.03.23]

UI polish batch:

- **Fixed:** Message view rendering ([`64548b1`](https://github.com/dappros/ethora-sdk-swift/commit/64548b1))
- **Fixed:** Footer button view ([`0f3c2eb`](https://github.com/dappros/ethora-sdk-swift/commit/0f3c2eb))
- **Fixed:** Open-chat view ([`9d79d67`](https://github.com/dappros/ethora-sdk-swift/commit/9d79d67))
- **Fixed:** Scroll behaviour ([`6bd509e`](https://github.com/dappros/ethora-sdk-swift/commit/6bd509e))
- **Fixed:** Image viewing ([`b1b9488`](https://github.com/dappros/ethora-sdk-swift/commit/b1b9488))

## [26.03.02]

- **New:** Push notifications support, code split ([`8b20dcd`](https://github.com/dappros/ethora-sdk-swift/commit/8b20dcd))
