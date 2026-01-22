//
//  App.swift
//  ChatAppExample
//
//  Example iOS app using XMPPChatSwift package
//

import SwiftUI
import Combine
import XMPPChatCore
import XMPPChatUI

@main
struct ChatAppExampleApp: App {
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
    
    init() {
        // Check if user is already authenticated from cache
        self.isAuthenticated = UserStore.shared.isAuthenticated
    }
    
    func initializeXMPPWithCachedUser() async {
        // Disconnect existing client if any
        if let existingClient = xmppClient {
            print("⚠️ Disconnecting existing XMPP client before creating new one")
            existingClient.disconnect()
            xmppClient = nil
        }
        
        guard let user = UserStore.shared.currentUser else {
            print("❌ No cached user available")
            return
        }
        
        let xmppUsername = user.xmppUsername ?? user.email ?? ""
        let xmppPassword = user.xmppPassword ?? ""
        
        guard !xmppUsername.isEmpty, !xmppPassword.isEmpty else {
            print("❌ Missing XMPP credentials in cached user")
            return
        }
        
        let settings = AppConfig.defaultXMPPSettings
        
        let client = XMPPClient(
            username: xmppUsername,
            password: xmppPassword,
            settings: settings
        )
        
        client.delegate = self
        self.xmppClient = client
        self.isAuthenticated = true
        
        // Register with ClientRegistry
        ClientRegistry.shared.setGlobalXMPPClient(client)
        
        print("✅ XMPP Client initialized with cached user: \(user.email ?? "unknown")")
    }
    
    func initializeXMPPWithLoggedInUser() async {
        // Disconnect existing client if any
        if let existingClient = xmppClient {
            print("⚠️ Disconnecting existing XMPP client before creating new one")
            existingClient.disconnect()
            xmppClient = nil
        }
        
        guard let user = UserStore.shared.currentUser else {
            print("❌ No user in UserStore after login")
            return
        }
        
        let xmppUsername = user.xmppUsername ?? user.email ?? ""
        let xmppPassword = user.xmppPassword ?? ""
        
        guard !xmppUsername.isEmpty, !xmppPassword.isEmpty else {
            print("❌ Missing XMPP credentials")
            return
        }
        
        let settings = AppConfig.defaultXMPPSettings
        
        let client = XMPPClient(
            username: xmppUsername,
            password: xmppPassword,
            settings: settings
        )
        
        client.delegate = self
        self.xmppClient = client
        self.isAuthenticated = true
        
        // Register with ClientRegistry
        ClientRegistry.shared.setGlobalXMPPClient(client)
        
        print("✅ XMPP Client initialized with logged in user: \(user.email ?? "unknown")")
    }
    
    func logout() async {
        print("🚪 Logging out...")
        
        // Disconnect XMPP
        xmppClient?.disconnect()
        xmppClient = nil
        
        // Clear UserStore (this clears cache too)
        UserStore.shared.clearUser()
        
        // Update state
        self.isAuthenticated = false
        
        print("✅ Logout complete. User data cleared from cache.")
    }
}

extension AppState: XMPPClientDelegate {
    func xmppClientDidConnect(_ client: XMPPClient) {
        print("✅ XMPP Client connected")
    }
    
    func xmppClientDidDisconnect(_ client: XMPPClient) {
        print("❌ XMPP Client disconnected")
    }
    
    func xmppClient(_ client: XMPPClient, didReceiveMessage message: Message) {
        print("📨 Received message: \(message.body)")
    }
    
    func xmppClient(_ client: XMPPClient, didReceiveStanza stanza: XMPPStanza) {
        // Handle stanza
    }
    
    func xmppClient(_ client: XMPPClient, didChangeStatus status: ConnectionStatus) {
        print("🔄 Connection status changed: \(status.rawValue)")
    }
}

