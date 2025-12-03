# Ethora Swift SDK (Beta)
Swift SDK for building **chat-enabled**, **AI-ready**, **super-app** style iOS applications using the **Ethora platform**.

The SDK provides a ready-made communication layer based on **XMPP messaging**, WebSockets, and Ethora APIs — along with UI components for chat screens, message bubbles, avatars, and typical in-app messaging behaviors.

---

## 🚀 Features (Beta)

### Messaging Layer
- ✔️ XMPP messaging  
- ✔️ WebSockets for presence + typing indicators  
- ✔️ Message send/receive  
- ✔️ User presence + “now typing”  
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

- ⏳ Edit / Delete messages  
- ⏳ Loading chat history  
- ⏳ Caching layer (~50% complete)  
- ⏳ Logout mechanism  
- ⏳ PDF preview (currently blank pages)  
- ⏳ Sending media (API request failing 401 auth error)  
- ⏳ Performance optimization  

---

## 📦 Installation (Swift Package Manager)

Add the package:

```
https://github.com/dappros/ethora-sdk-swift
```

Or in `Package.swift`:

```swift
.dependencies([
    .package(url: "https://github.com/dappros/ethora-sdk-swift", branch: "main")
])
```

Import in your project:

```swift
import EthoraSDK
```

---

## 🔧 Quick Start Example

### 1. Initialize the SDK
```swift
let config = EthoraConfig(
    apiBaseURL: "https://api.ethora.com",
    xmppHost: "xmpp.ethora.com",
    xmppPort: 5222
)

Ethora.shared.initialize(config: config)
```

### 2. Authenticate User
```swift
Ethora.shared.login(username: "john", password: "mypassword") { result in
    switch result {
    case .success(let profile):
        print("Logged in:", profile.username)
    case .failure(let error):
        print("Login failed:", error)
    }
}
```

### 3. Send a Message
```swift
Ethora.shared.messaging.sendMessage(
    to: "room123",
    text: "Hello from Swift!"
)
```

### 4. Listen for Incoming Messages
```swift
Ethora.shared.messaging.onMessageReceived = { message in
    print("New message:", message.text)
}
```

### 5. Use the Built-In Chat UI
```swift
let chatVC = EthoraChatViewController(roomId: "room123")
navigationController?.pushViewController(chatVC, animated: true)
```

---

## 📐 Architecture Overview

**Layers:**
1. Networking (REST API, WebSockets, XMPP)  
2. Core SDK (authentication, message manager, caching)  
3. UI Layer (chat screen, bubbles, avatars, typing)

---

## 🗺️ Roadmap

| Feature | Status |
|--------|--------|
| Edit/delete messages | 🔄 In progress |
| Message history loading | 🔄 In progress |
| Logout | 🔄 In progress |
| Caching | 50% done |
| Media uploads | ⚠️ 401 auth issue |
| PDF preview | ⚠️ Renders blank |
| UI customization | Planned |
| AI agent integration | Planned |
| Calls / Voice notes | Planned |

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

**Contact:** https://ethora.com/contact/
