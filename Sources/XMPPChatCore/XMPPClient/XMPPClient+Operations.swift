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
        guard let stream = xmppStream, status == .online else { return }
        let stanza = XMPPStanza(name: "presence")
        stream.send(stanza)
    }
    
    /// Send MUC presence to a single room so the user becomes an occupant.
    /// Must be called before `sendTextMessage` / `sendGetHistory` for that room.
    public func sendPresenceToRoom(roomJID: String) async {
        await self.operations.presenceInRoom(roomJID: roomJID)
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
        // This calls allRoomPresences which internally calls presenceInRoom for each room
        await self.operations.allRoomPresences(roomJIDs: roomJIDs)
    }
    
    // MARK: - Wrapper Methods
    internal func wrapWithConnectionCheck<T>(_ operation: () async throws -> T) async throws -> T {
        try await ensureConnected()
        return try await operation()
    }
}
