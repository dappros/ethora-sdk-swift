//
//  XMPPClient+Operations.swift
//  XMPPChatCore
//
//  Extra connection/presence helpers. Core client + stream delegate live in XMPPClient.swift
//  (duplicate extensions caused “invalid redeclaration” and private access errors).
//

import Foundation

extension XMPPClient {
    /// Send global `<presence/>` stanza to XMPP server (announce online).
    public func sendGlobalPresence() {
        guard let stream = xmppStream, status == .online else {
            print("[XMPPClient] sendGlobalPresence SKIPPED — stream: \(xmppStream != nil), status: \(status.rawValue)")
            return
        }
        let stanza = XMPPStanza(name: "presence")
        stream.send(stanza)
        print("[XMPPClient] sendGlobalPresence OK — <presence/> sent")
    }

    /// Send MUC presence to a single room so the user becomes an occupant.
    public func sendPresenceToRoom(roomJID: String) async {
        await operations.presenceInRoom(roomJID: roomJID)
    }

    /// Покинуть комнату MUC — посылает `<presence type="unavailable"
    /// to="room/nick"/>`. Использование — поведение «Leave» в списке чатов
    /// (как на вебе): сервер перестаёт слать этому ресурсу broadcast'ы из
    /// этой комнаты, но сам чат и остальные участники не трогаются.
    public func leaveRoom(roomJID: String) async {
        await operations.leaveRoom(roomJID: roomJID)
    }

    /// Ensures connection, sends global presence, joins rooms, waits for presence acks.
    @discardableResult
    public func joinRoomsAndWait(roomJIDs: [String], timeout: TimeInterval = 3.5) async -> [String] {
        guard !roomJIDs.isEmpty else { return [] }
        print("[XMPPClient] joinRoomsAndWait START — rooms.count=\(roomJIDs.count), timeout=\(timeout)s")

        do {
            try await ensureConnected(timeout: max(1.0, timeout))
            print("[XMPPClient] joinRoomsAndWait connected, status=\(status.rawValue)")
        } catch {
            print("[XMPPClient] joinRoomsAndWait: not connected (\(error))")
            return roomJIDs
        }

        sendGlobalPresence()
        await sendPresenceToAllRooms(roomJIDs: roomJIDs)

        let unresolved = await waitForRoomPresenceResponses(roomJIDs: roomJIDs, timeout: timeout)
        if !unresolved.isEmpty {
            print("[XMPPClient] joinRoomsAndWait unresolved rooms: \(unresolved.joined(separator: ", "))")
        } else {
            print("[XMPPClient] joinRoomsAndWait COMPLETE — all rooms acknowledged")
        }
        return unresolved
    }

    /// After rooms are loaded from API — presence with retry while waiting for server acks.
    public func sendPresenceToAllRooms(roomJIDs: [String]) async {
        print("[XMPPClient] sendPresenceToAllRooms START — rooms.count=\(roomJIDs.count)")
        if !roomJIDs.isEmpty {
            print("[XMPPClient] roomJIDs=\(roomJIDs.joined(separator: ", "))")
        }

        await operations.allRoomPresences(roomJIDs: roomJIDs)

        var pending = await waitForRoomPresenceResponses(roomJIDs: roomJIDs, timeout: 2.0)
        print("[XMPPClient] sendPresenceToAllRooms first wait pending=\(pending.count)")

        if !pending.isEmpty {
            print("[XMPPClient] Retrying presence for pending rooms: \(pending.joined(separator: ", "))")
            await operations.allRoomPresences(roomJIDs: pending)
            pending = await waitForRoomPresenceResponses(roomJIDs: pending, timeout: 1.5)
            print("[XMPPClient] sendPresenceToAllRooms second wait pending=\(pending.count)")
        }

        if !pending.isEmpty {
            print("[XMPPClient] Presence ack timeout for rooms: \(pending.joined(separator: ", "))")
        } else {
            print("[XMPPClient] sendPresenceToAllRooms COMPLETE — all rooms acknowledged")
        }
    }

    internal func waitForRoomPresenceResponses(roomJIDs: [String], timeout: TimeInterval) async -> [String] {
        let normalized = roomJIDs.map { $0.components(separatedBy: "/").first ?? $0 }
        let start = Date()
        print("[XMPPClient] waitForRoomPresenceResponses START — timeout=\(timeout)s")
        while Date().timeIntervalSince(start) < timeout {
            let missing = normalized.filter { !hasPresenceResponseForRoom($0) }
            if missing.isEmpty {
                print("[XMPPClient] waitForRoomPresenceResponses COMPLETE — no missing rooms")
                return []
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        let unresolved = normalized.filter { !hasPresenceResponseForRoom($0) }
        print("[XMPPClient] waitForRoomPresenceResponses TIMEOUT — unresolved=\(unresolved.joined(separator: ", "))")
        return unresolved
    }
}
