//
//  XMPPClient+Operations.swift
//  XMPPChatCore
//

import Foundation

extension XMPPClient {
    // MARK: - Connection Status and Utilities
    public func ensureConnected(timeout: TimeInterval = 10.0) async throws {
        guard status != .online else { return }
        
        if status == .offline || status == .error {
            logStep("ensureConnected:trigger-reconnect:\(status.rawValue)")
            scheduleReconnect(reason: "ensure-connected")
            throw XMPPError.notConnected
        }
        
        if status == .connecting {
            // Wait for connection with timeout
            let startTime = Date()
            while status == .connecting {
                if Date().timeIntervalSince(startTime) > timeout {
                    throw XMPPError.connectionTimeout
                }
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
            
            if status != .online {
                throw XMPPError.connectionError
            }
        }
    }
    
    // MARK: - Message Queue
    internal func enqueue(_ task: @escaping () async -> Bool) async -> Bool {
        return await withCheckedContinuation { continuation in
            messageQueue.append {
                let result = await task()
                continuation.resume(returning: result)
                return result
            }
            Task {
                await processQueue()
            }
        }
    }
    
    internal func processQueue() async {
        guard !processingQueue else { return }
        processingQueue = true
        defer { processingQueue = false }
        
        while !messageQueue.isEmpty {
            do {
                try await ensureConnected()
            } catch {
                break
            }
            
            guard let next = messageQueue.first else { break }
            let ok = await next()
            
            if ok {
                messageQueue.removeFirst()
            } else {
                break
            }
        }
        
        if !messageQueue.isEmpty && status == .online {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            await processQueue()
        }
    }
    
    internal func withIdLock<T>(_ id: String?, _ fn: () async throws -> T) async throws -> T {
        guard let id = id else { return try await fn() }
        guard !inFlightIds.contains(id) else {
            throw XMPPError.duplicateRequest
        }
        inFlightIds.insert(id)
        defer {
            inFlightIds.remove(id)
        }
        return try await fn()
    }

    // MARK: - Public Presence API
    
    /// Send global `<presence/>` stanza to XMPP server (announce online).
    /// Called automatically after auth, but can be called manually
    /// when integrating ChatCore without ChatUI.
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
    /// Must be called before `sendTextMessage` / `sendGetHistory` for that room.
    public func sendPresenceToRoom(roomJID: String) async {
        await self.operations.presenceInRoom(roomJID: roomJID)
    }
    
    /// One-shot helper for ChatCore-only integrations:
    /// ensures connection is online, sends global presence, joins rooms,
    /// and waits for room presence acknowledgements.
    /// - Returns: List of rooms that still did not return presence ack.
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
    
    // MARK: - Internal Presence
    internal func sendAllPresencesAndMarkReady() async {
        presencesReady = false
        
        await allRoomPresencesStanza()
        
        presencesReady = true
    }
    
    internal func allRoomPresencesStanza() async {
        // Note: In TypeScript, this gets rooms from store.getState().rooms.rooms
        // In Swift, we'll send presence to rooms after they're loaded via API
        // This is called from sendAllPresencesAndMarkReady, but actual room presence
        // will be sent later when rooms are loaded
    }
    
    // Public method to send presence to all rooms (called after rooms are loaded)
    // In Swift, we pass roomJIDs after loading from API
    public func sendPresenceToAllRooms(roomJIDs: [String]) async {
        print("[XMPPClient] sendPresenceToAllRooms START — rooms.count=\(roomJIDs.count)")
        if !roomJIDs.isEmpty {
            print("[XMPPClient] roomJIDs=\(roomJIDs.joined(separator: ", "))")
        }
        
        // First attempt: send presence to each room.
        await self.operations.allRoomPresences(roomJIDs: roomJIDs)
        
        // Wait for server presence echoes/acks to reduce race with first history/send calls.
        var pending = await waitForRoomPresenceResponses(roomJIDs: roomJIDs, timeout: 2.0)
        print("[XMPPClient] sendPresenceToAllRooms first wait pending=\(pending.count)")
        
        // Retry missing rooms once, then wait again briefly.
        if !pending.isEmpty {
            print("[XMPPClient] Retrying presence for pending rooms: \(pending.joined(separator: ", "))")
            await self.operations.allRoomPresences(roomJIDs: pending)
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
    
    // MARK: - Wrapper Methods
    internal func wrapWithConnectionCheck<T>(_ operation: () async throws -> T) async throws -> T {
        try await ensureConnected()
        return try await operation()
    }
}
