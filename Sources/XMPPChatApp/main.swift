//
//  main.swift
//  XMPPChatApp
//
//  Executable app for testing XMPP connection
//

import Foundation
import XMPPChatCore

// Test credentials
let email = "yukiraze9@gmail.com"
let password = "Qwerty123"

//print("🚀 Starting XMPP Chat Test App")
//print("📧 Email: \(email)")
//print("")

// Step 1: Login first
//print("🔐 Step 1: Logging in with email...")
//print("")

Task {
    do {
        let loginResponse = try await AuthAPI.loginWithEmail(
            email: email,
            password: password
        )
        
        // Save to UserStore
        await UserStore.shared.setUser(from: loginResponse)
        
        //print("")
        //print("✅ Login successful! User stored in UserStore")
        //print("")
        
        // Step 2: Now connect XMPP
        //print("🔐 Step 2: Connecting to XMPP server...")
        //print("")
        
        let user = await UserStore.shared.currentUser
        let xmppUsername = user?.xmppUsername ?? email
        let xmppPassword = user?.xmppPassword ?? password
        
        let settings = XMPPSettings(
            devServer: "wss://xmpp.ethoradev.com:5443/ws",
            host: "xmpp.ethoradev.com",
            conference: "conference.xmpp.ethoradev.com"
        )
        
        let client = XMPPClient(
            username: xmppUsername,
            password: xmppPassword,
            settings: settings
        )
        
        class TestDelegate: XMPPClientDelegate {
            func xmppClientDidConnect(_ client: XMPPClient) {
                //print("✅ XMPP Client connected successfully!")
                //print("📊 Connection status: \(client.status.rawValue)")
            }
            
            func xmppClientDidDisconnect(_ client: XMPPClient) {
                //print("❌ XMPP Client disconnected")
            }
            
            func xmppClient(_ client: XMPPClient, didReceiveMessage message: Message) {
                //print("📨 Received message: \(message.body)")
            }
            
            func xmppClient(_ client: XMPPClient, didReceiveStanza stanza: XMPPStanza) {
                // Handle stanza
            }
            
            func xmppClient(_ client: XMPPClient, didChangeStatus status: ConnectionStatus) {
                //print("🔄 Connection status changed: \(status.rawValue)")
            }
        }
        
        let delegate = TestDelegate()
        client.delegate = delegate
        
        // Step 3: Test loading rooms
        //print("")
        //print("📋 Step 3: Testing room loading...")
        //print("")
        
        Task {
            do {
                let rooms = try await RoomsAPI.getRooms()
                //print("✅ Loaded \(rooms.count) rooms!")
                for room in rooms {
                    //print("   - \(room.title) (\(room.jid))")
                }
            } catch {
                //print("❌ Failed to load rooms: \(error)")
            }
        }
        
    } catch {
        //print("❌ Login failed: \(error)")
        if let authError = error as? AuthAPIError {
            //print("   Error: \(authError.localizedDescription)")
        }
    }
}

// Keep the app running
//print("⏳ Waiting for operations...")
//print("Press Ctrl+C to exit")
//print("")

// Run the main run loop
let runLoop = RunLoop.current
runLoop.run()
