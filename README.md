<!-- @format -->

# Ethora Swift SDK (Beta)

Swift SDK for building **chat-enabled**, **AI-ready**, **super-app** style iOS applications using the **Ethora platform**.

The SDK provides a ready-made communication layer based on **XMPP messaging**, WebSockets, and Ethora APIs — along with UI components for chat screens, message bubbles, avatars, and typical in-app messaging behaviors.

---

## 🚀 Features (Beta)

### Messaging Layer

- ✔️ XMPP messaging
- ✔️ WebSockets for presence + typing indicators
- ✔️ Message send/receive
- ✔️ User presence + "now typing"
- ✔️ Basic message attachments (in progress)

### Ethora API Integration

- ✔️ Authentication & session management
- ✔️ API client for Ethora backend
- ✔️ User profiles, avatars, chat room logic

### UI Components

- ✔️ Standard chat UI screen
- ✔️ Message bubbles
- ✔️ User avatars
- ✔️ Typing indicator

---

## 🛠️ Work in Progress

The SDK is actively evolving. Current beta limitations:

- ⏳ Logout mechanism
- ⏳ PDF preview (currently blank pages)

---

## 📦 Installation

### Requirements

- iOS 15.0+ or macOS 12.0+
- Swift 5.9+
- Xcode 14.0+

### Option 1: Add Package in Xcode

1. **Open your Xcode project**

2. **Add Package Dependency:**

   - Go to **File → Add Package Dependencies...**
   - Enter the repository URL:
     ```
     https://github.com/dappros/ethora-sdk-swift
     ```
   - Click **Add Package**

3. **Select Package Products:**
   - ✅ Check **XMPPChatCore** (required)
   - ✅ Check **XMPPChatUI** (required for UI components)
   - Make sure they're added to your app target
   - Click **Add Package**

### Option 2: Add via Package.swift

If you're using a Swift Package Manager project, add the dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/dappros/ethora-sdk-swift", branch: "main")
]
```

Then add the products to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "XMPPChatCore", package: "ethora-sdk-swift"),
        .product(name: "XMPPChatUI", package: "ethora-sdk-swift")
    ]
)
```

### Import the Modules

In your Swift files, import the modules you need:

```swift
import XMPPChatCore  // Core functionality (XMPP, API, models)
import XMPPChatUI    // UI components (chat views, room list)
```

---

## 🔧 Quick Start Guide

### Step 1: Configure XMPP Settings

First, configure your XMPP connection settings. You can use the default settings or customize them:

```swift
import XMPPChatCore

// Option 1: Use default settings (recommended for development)
let settings = AppConfig.defaultXMPPSettings

// Option 2: Customize XMPP settings
let customSettings = XMPPSettings(
    devServer: "wss://xmpp.ethoradev.com:5443/ws",
    host: "xmpp.ethoradev.com",
    conference: "conference.xmpp.ethoradev.com",
    xmppPingOnSendEnabled: true
)
```

### Step 2: Authenticate User

Authenticate with the Ethora API using email and password:

```swift
import XMPPChatCore

Task {
    do {
        // Login with email and password
        let loginResponse = try await AuthAPI.loginWithEmail(
            email: "yukiraze9@gmail.com",
            password: "Qwerty123"
        )

        // Save user data to UserStore (this also caches the session)
        await UserStore.shared.setUser(from: loginResponse)

        print("✅ Login successful!")
        print("User ID: \(loginResponse.user.id)")
        print("Token saved: \(UserStore.shared.token != nil)")

    } catch {
        print("❌ Login failed: \(error)")
    }
}
```

### Step 3: Initialize XMPP Client

After successful authentication, initialize the XMPP client:

```swift
import XMPPChatCore

// Get user from UserStore
guard let user = UserStore.shared.currentUser else {
    print("❌ No user found. Please login first.")
    return
}

// Extract XMPP credentials
let xmppUsername = user.xmppUsername ?? user.email ?? ""
let xmppPassword = user.xmppPassword ?? ""

guard !xmppUsername.isEmpty, !xmppPassword.isEmpty else {
    print("❌ Missing XMPP credentials")
    return
}

// Create XMPP client
let settings = AppConfig.defaultXMPPSettings
let xmppClient = XMPPClient(
    username: xmppUsername,
    password: xmppPassword,
    settings: settings
)

// Set delegate to receive connection events and messages
xmppClient.delegate = self

// The client will automatically connect when initialized
```

### Step 4: Implement XMPPClientDelegate

Implement the delegate to handle connection events and incoming messages:

```swift
import XMPPChatCore

extension YourViewController: XMPPClientDelegate {
    func xmppClientDidConnect(_ client: XMPPClient) {
        print("✅ XMPP Client connected")
        // Update UI, load rooms, etc.
    }

    func xmppClientDidDisconnect(_ client: XMPPClient) {
        print("❌ XMPP Client disconnected")
        // Handle disconnection
    }

    func xmppClient(_ client: XMPPClient, didReceiveMessage message: Message) {
        print("📨 Received message: \(message.body)")
        // Update UI with new message
    }

    func xmppClient(_ client: XMPPClient, didChangeStatus status: ConnectionStatus) {
        print("🔄 Connection status: \(status.rawValue)")
        // Update connection status in UI
    }

    func xmppClient(_ client: XMPPClient, didReceiveStanza stanza: XMPPStanza) {
        // Handle other XMPP stanzas if needed
    }
}
```

### Step 5: Use the Chat UI Components

The SDK provides ready-to-use SwiftUI components:

```swift
import SwiftUI
import XMPPChatCore
import XMPPChatUI

struct ChatView: View {
    let xmppClient: XMPPClient

    var body: some View {
        // Room List View - shows all chat rooms
        RoomListView(
            viewModel: RoomListViewModel(
                client: xmppClient,
                currentUserId: UserStore.shared.currentUser?.id ?? ""
            )
        )
    }
}

// Or use ChatRoomView for a specific room
struct SingleChatView: View {
    let roomId: String
    let xmppClient: XMPPClient

    var body: some View {
        ChatRoomView(
            viewModel: ChatRoomViewModel(
                roomId: roomId,
                client: xmppClient
            )
        )
    }
}
```

## 📱 Complete Example

```swift
import SwiftUI
import XMPPChatCore
import XMPPChatUI

@main
struct MyApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}

@MainActor
class AppState: ObservableObject {
    @Published var xmppClient: XMPPClient?
    @Published var isAuthenticated: Bool = false

    func login(email: String, password: String) async {
        do {
            // Step 1: Authenticate
            let loginResponse = try await AuthAPI.loginWithEmail(
                email: email,
                password: password
            )

            // Step 2: Save user
            await UserStore.shared.setUser(from: loginResponse)

            // Step 3: Initialize XMPP
            guard let user = UserStore.shared.currentUser else { return }

            let xmppClient = XMPPClient(
                username: user.xmppUsername ?? user.email ?? "",
                password: user.xmppPassword ?? "",
                settings: AppConfig.defaultXMPPSettings
            )

            xmppClient.delegate = self
            self.xmppClient = xmppClient
            self.isAuthenticated = true

        } catch {
            print("Login failed: \(error)")
        }
    }
}

extension AppState: XMPPClientDelegate {
    func xmppClientDidConnect(_ client: XMPPClient) {
        print("✅ Connected")
    }

    func xmppClient(_ client: XMPPClient, didReceiveMessage message: Message) {
        print("📨 \(message.body)")
    }

    // ... other delegate methods
}
```

For a complete working example, see the `Examples/ChatAppExample` folder in this repository.

---

## 📐 Architecture Overview

The SDK is organized into two main modules:

### XMPPChatCore

Core functionality including:

- **Networking**: `AuthAPI`, `RoomsAPI` for REST API calls
- **XMPP Client**: `XMPPClient` for real-time messaging
- **Models**: `User`, `Message`, `Room`, `XMPPSettings`
- **Persistence**: `UserStore`, `MessageCache` for local storage
- **Configuration**: `AppConfig` for default settings

### XMPPChatUI

SwiftUI components including:

- **RoomListView**: List of all chat rooms
- **ChatRoomView**: Individual chat room interface
- **BannerSettingsView**: Settings management

### Key Components

**UserStore**: Manages user authentication state and caching

```swift
// Check if user is authenticated
if UserStore.shared.isAuthenticated {
    // User is logged in
}

// Get current user
let user = UserStore.shared.currentUser

// Get auth token
let token = UserStore.shared.token
```

**XMPPClient**: Handles XMPP connection and messaging

```swift
let client = XMPPClient(
    username: "user@example.com",
    password: "password",
    settings: XMPPSettings(...)
)
client.delegate = self
```

**AppConfig**: Provides default configuration

```swift
// Default XMPP settings
let settings = AppConfig.defaultXMPPSettings

// Default API base URL
let baseURL = AppConfig.defaultBaseURL

// App token (can be overridden via ETHORA_APP_TOKEN env var)
let token = AppConfig.appToken
```

---

## 🔧 Configuration

### Environment Variables

You can override default configuration using environment variables:

- `ETHORA_APP_TOKEN`: Override the default app token
- `ETHORA_DEV_USER_TOKEN`: Override the default dev user token

### Custom XMPP Settings

```swift
let settings = XMPPSettings(
    devServer: "wss://your-xmpp-server.com:5443/ws",
    host: "your-xmpp-server.com",
    conference: "conference.your-xmpp-server.com",
    xmppPingOnSendEnabled: true  // Optional: enable ping on send
)
```

### API Configuration

The SDK uses `AppConfig.defaultBaseURL` by default (`https://api.ethoradev.com/v1`). To use a different API endpoint, you'll need to modify the API classes or use dependency injection.

---

## 📚 Additional Resources

- See `Examples/ChatAppExample` for a complete working example
- Check `INSTALLATION.md` for detailed installation steps
- Review source code in `Sources/XMPPChatCore` and `Sources/XMPPChatUI`

---

## 🤝 Contributing

We welcome:

- PRs
- Issues
- Feature requests
- Bug reports

---

## 📄 License

MIT License.

---

## 🆘 Troubleshooting

### Common Issues

**"No user found" error:**

- Make sure you've called `UserStore.shared.setUser(from: loginResponse)` after successful login
- Verify the login response contains all required user data

**XMPP connection fails:**

- Check your XMPP credentials (`xmppUsername` and `xmppPassword`)
- Verify XMPP server settings are correct
- Ensure network connectivity

**401 Authentication errors:**

- Verify your app token is correct
- Check that the user token is being sent in API requests
- Ensure `UserStore.shared.token` is set after login

**Messages not appearing:**

- Verify XMPP client is connected (`xmppClientDidConnect` was called)
- Check that you're listening to the correct room JID
- Ensure delegate methods are properly implemented

---

**Contact:** https://ethora.com/contact/
