//
//  main.swift
//  XMPPChatApp
//
//  Executable app for testing XMPP connection flow:
//  Login → Connect XMPP → Global Presence → Get Rooms → Presence in Room → Send Message
//

import Foundation
import XMPPChatCore

setbuf(stdout, nil)

let email = "yukiraze9@gmail.com"
let password = "Qwerty123"

print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("  XMPP Connection Flow Test")
print("  Email: \(email)")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

Task {
    do {
        // ── Step 1: REST Login ──────────────────────────────
        print("\n[1/6] Logging in...")
        let loginResponse = try await AuthAPI.loginWithEmail(
            email: email,
            password: password
        )
        await UserStore.shared.setUser(from: loginResponse)

        let user = await UserStore.shared.currentUser
        let xmppUsername = user?.xmppUsername ?? email
        let xmppPassword = user?.xmppPassword ?? password
        print("  ✅ Login OK")
        print("  xmppUsername: \(xmppUsername)")

        // ── Step 2: Connect XMPP ───────────────────────────
        print("\n[2/6] Connecting to XMPP...")
        let client = XMPPClient(
            username: xmppUsername,
            password: xmppPassword,
            settings: XMPPSettings(
                devServer: "wss://xmpp.ethoradev.com:5443/ws",
                host: "xmpp.ethoradev.com",
                conference: "conference.xmpp.ethoradev.com"
            )
        )

        class TestDelegate: XMPPClientDelegate {
            func xmppClientDidConnect(_ client: XMPPClient) {
                print("  ✅ Delegate: connected")
            }
            func xmppClientDidDisconnect(_ client: XMPPClient) {
                print("  ⚠️  Delegate: disconnected")
            }
            func xmppClient(_ client: XMPPClient, didReceiveMessage message: Message) {
                print("  📨 Incoming message: \(message.body)")
            }
            func xmppClient(_ client: XMPPClient, didReceiveStanza stanza: XMPPStanza) {}
            func xmppClient(_ client: XMPPClient, didChangeStatus status: ConnectionStatus) {
                print("  🔄 Status: \(status.rawValue)")
            }
        }
        let delegate = TestDelegate()
        client.delegate = delegate

        // ── Step 3: Wait for full connection ────────────────
        print("\n[3/6] Waiting for isFullyConnected()...")
        let timeout: TimeInterval = 15
        let start = Date()
        while !client.isFullyConnected() {
            if Date().timeIntervalSince(start) > timeout {
                print("  ❌ Timeout — could not connect in \(Int(timeout))s")
                print("     status: \(client.status.rawValue)")
                exit(1)
            }
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        print("  ✅ Fully connected (status: \(client.status.rawValue))")

        // ── Step 4: Global presence ─────────────────────────
        print("\n[4/6] Sending global <presence/>...")
        client.sendGlobalPresence()

        // ── Step 5: Get rooms + presence into each ──────────
        print("\n[5/6] Loading rooms from API...")
        let rooms = try await RoomsAPI.getRooms()
        print("  ✅ Loaded \(rooms.count) rooms")

        if rooms.isEmpty {
            print("  ⚠️  No rooms — nothing to test. Done.")
            exit(0)
        }

        for room in rooms {
            print("  → Sending presence to: \(room.jid)")
            await client.sendPresenceToRoom(roomJID: room.jid)
        }
        print("  ✅ Presence sent to all \(rooms.count) rooms")

        try await Task.sleep(nanoseconds: 1_000_000_000)

        // ── Step 6: Send test message to first room ─────────
        let targetRoom = rooms[0]
        let testMessage = "Test from Swift SDK — \(Date())"
        print("\n[6/6] Sending test message to '\(targetRoom.title)'...")
        print("  roomJID: \(targetRoom.jid)")
        print("  message: \(testMessage)")

        client.operations.sendTextMessage(
            roomJID: targetRoom.jid,
            firstName: user?.firstName ?? "Test",
            lastName: user?.lastName ?? "User",
            photo: user?.profileImage ?? "",
            walletAddress: user?.walletAddress ?? "",
            userMessage: testMessage
        )
        print("  ✅ Message sent (check the other client to confirm)")

        print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("  All steps completed. Listening for messages...")
        print("  Press Ctrl+C to exit")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        _ = delegate

    } catch {
        print("\n❌ Error: \(error)")
        if let authError = error as? AuthAPIError {
            print("   Details: \(authError.localizedDescription)")
        }
        exit(1)
    }
}

RunLoop.current.run()
