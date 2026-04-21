# Ethora iOS Chat Package Features

## Package Scope
Ethora Swift chat package is delivered as two SPM libraries:
- `XMPPChatCore`: networking, XMPP transport, auth/API integration, stores, and chat domain models.
- `XMPPChatUI`: ready-to-use SwiftUI chat screens and components built on top of `XMPPChatCore`.

Distribution flexibility for host apps:
- Swift Package Manager via Xcode UI.
- Swift Package dependency in `Package.swift`.
- Manual source copy (`Sources/XMPPChatCore`, `Sources/XMPPChatUI`) for enterprise/offline/vendor-policy constraints.

Platform support (from `Package.swift`):
- iOS 15+

## Core Product Features

### 1. Chat Connection and Transport
- Native XMPP client over WebSocket (`Starscream`-based).
- Connect, disconnect, auth flow, and global presence publishing.
- Room presence join for one or many rooms.
- Connection state management for UI status surfaces.
- Message/history stanza parsing with dedicated operation handlers.

### 2. Authentication and Session Modes
- JWT login flow support via API + config (`JWTLoginConfig`).
- Email/password login API flow.
- Custom login callback support for host app-defined auth.
- User session persistence through `UserStore`.
- Optional token refresh strategy with custom refresh function.

### 3. Room Management
- Load rooms from backend API.
- Single-room mode (`disableRooms` + `initialRoomJID`) for embedded support chat use cases.
- Multi-room list mode with sorted rooms by recent activity.
- Room search by title/last message content.
- Create/report/delete room APIs.
- Add/remove members APIs for room access management.
- Push-triggered room deep-open behavior support.

### 4. Messaging Experience
- Real-time incoming/outgoing text messages.
- MAM history loading with pagination and load-more behavior.
- Pull-to-refresh and retry handling for history failures.
- Pending message deduplication against confirmed server messages.
- Message editing and deletion support.
- Emoji reactions per message.
- Reply/thread-related message model support and thread view entry.
- Typing indicator with configurable rendering.
- Unread tracking per room with host-level unread propagation hooks:
  - `ChatWrapperView(... onUnreadCountChanged:)` for immediate tab/app badge updates.
  - `RoomStore.shared.$totalUnreadCount` for reactive app-shell badge binding.
- Message status indicators and delivery-state-aware rendering hooks.

### 5. Media and Rich Content
- Media message support in message model and UI.
- Image viewer and image gallery flows.
- Full-screen video playback view.
- PDF viewer and full-screen PDF view.
- Audio message recording/playback components with waveform view support.
- URL preview card component.
- Markdown text rendering component.
- QR code component available for chat-related extensions.

### 6. Notifications
- Push subscription flow with FCM token handling.
- Backend push subscription management.
- Room-level push subscription refresh logic.
- Pending push room JID store to route user into the right room.
- Message notification model and notification-related config surfaces.

### 7. UX and Operational Resilience
- Wrapper-level initialization/loading phases.
- Connection status banner for online/offline awareness.
- Empty/error/loading states for room list and message list.
- Built-in retry states for room loading (`EnableRoomsRetryConfig`).
- Retry/backoff strategy for history load errors.
- Defensive fallback states when user/session context is missing.

### 8. Customization and White-Label Controls
- Theme colors and bubble style customization.
- Background color/image chat customization.
- Header visibility and behavior controls.
- Header title overrides by room JID.
- Disable switches for rooms, media, room menu/config, new chat button, chat info pieces, typing indicator, and profile interactions.
- Secondary send button customization (custom label/style/behavior).
- Message text filter hook for moderation/pre-processing.
- Chat event handler hooks and custom component injection points.
- Translation config (`TranslationsConfig`) for multilingual UX tuning.

### 9. Moderation and Safety Surfaces
- Report room API.
- Report message API.
- UI modals for reporting and blocked users management.
- Chat info/room settings/member management screens for admin workflows.

### 10. Persistence and Performance
- Config persistence through `ConfigStore` (`UserDefaults`-backed codable fields).
- User/session persistence through `UserStore`.
- Room cache persistence through `RoomStore`.
- Message cache support.
- Message list virtualization and queue/priority helpers.
- Memory/perf utility helpers and bounded room-message persistence behavior.

## Developer Experience Features
- Distribution options for different compliance and delivery constraints:
  - Swift Package Manager in Xcode.
  - `Package.swift` dependency integration.
  - Manual source-copy path for enterprise/offline/vendor-policy environments.
- Drop-in host unread integration ergonomics:
  - `onUnreadCountChanged` callback from `ChatWrapperView`.
  - `RoomStore.shared.$totalUnreadCount` for global reactive badge updates.
- Example apps (`Examples/`) for integration and playground testing.
- `ChatWrapperView` integration path for fast host-app embedding.
- Programmatic APIs for direct `XMPPChatCore` usage when custom UI is required.

## Recommended Product Positioning
- Best fit: white-label in-app chat, customer support chat, and community/group chat in iOS apps.
- Fastest time-to-value: use `ChatWrapperView` + JWT flow + single-room mode first, then expand into multi-room and advanced customization.
- Monetization-friendly hooks: custom login, feature flags, push, moderation/reporting, and configurable UI surfaces support freemium/pro-tier packaging at app level.
