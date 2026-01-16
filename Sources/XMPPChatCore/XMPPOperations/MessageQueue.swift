//
//  MessageQueue.swift
//  XMPPChatCore
//
//  Message sending queue with retry logic and blocking support
//

import Foundation

public class MessageQueue {
    private var queue: [QueuedMessage] = []
    private var processing: Bool = false
    private var blockedRooms: Set<String> = []
    private var timeoutTimers: [String: Timer] = [:]
    
    private let maxRetries: Int = 3
    private let retryDelay: TimeInterval = 2.0
    private let defaultTimeout: TimeInterval = 300.0 // 5 minutes
    
    public var blockMessageSendingWhenProcessing: BlockMessageSendingConfig?
    
    public init() {}
    
    // MARK: - Queue Management
    
    /// Add message to queue
    public func enqueue(_ message: QueuedMessage) {
        queue.append(message)
        processQueue()
    }
    
    /// Process queue
    private func processQueue() {
        guard !processing else { return }
        guard !queue.isEmpty else { return }
        
        processing = true
        
        Task {
            while !queue.isEmpty {
                let message = queue.removeFirst()
                
                // Check if room is blocked
                if isRoomBlocked(message.roomJID) {
                    // Re-queue message
                    queue.append(message)
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second
                    continue
                }
                
                // Try to send message
                do {
                    try await sendMessage(message)
                    processing = false
                } catch {
                    // Retry logic
                    if message.retryCount < maxRetries {
                        message.retryCount += 1
                        queue.append(message)
                        try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                    } else {
                        // Max retries reached, call failure handler
                        message.onFailure?(error)
                        processing = false
                    }
                }
            }
            
            processing = false
        }
    }
    
    /// Send message (to be implemented by caller)
    private func sendMessage(_ message: QueuedMessage) async throws {
        // This should be implemented by the caller
        // For now, we'll call the send function directly
        try await message.sendFunction()
    }
    
    // MARK: - Blocking Support
    
    /// Check if room is blocked
    public func isRoomBlocked(_ roomJID: String) -> Bool {
        return blockedRooms.contains(roomJID)
    }
    
    /// Block room from sending messages
    public func blockRoom(_ roomJID: String, timeout: TimeInterval? = nil) {
        blockedRooms.insert(roomJID)
        
        let timeoutDuration = timeout ?? blockMessageSendingWhenProcessing?.timeout ?? defaultTimeout
        
        // Set timeout timer
        let timer = Timer.scheduledTimer(withTimeInterval: timeoutDuration, repeats: false) { [weak self] _ in
            self?.unblockRoom(roomJID)
            self?.blockMessageSendingWhenProcessing?.onTimeout?(roomJID)
        }
        
        timeoutTimers[roomJID] = timer
    }
    
    /// Unblock room
    public func unblockRoom(_ roomJID: String) {
        blockedRooms.remove(roomJID)
        timeoutTimers[roomJID]?.invalidate()
        timeoutTimers.removeValue(forKey: roomJID)
        
        // Resume processing
        processQueue()
    }
    
    /// Clear all blocks
    public func clearBlocks() {
        blockedRooms.removeAll()
        timeoutTimers.values.forEach { $0.invalidate() }
        timeoutTimers.removeAll()
    }
    
    /// Clear queue
    public func clear() {
        queue.removeAll()
        processing = false
    }
}

// MARK: - Queued Message

public class QueuedMessage {
    public let roomJID: String
    public let sendFunction: () async throws -> Void
    public let onSuccess: (() -> Void)?
    public let onFailure: ((Error) -> Void)?
    public var retryCount: Int = 0
    
    public init(
        roomJID: String,
        sendFunction: @escaping () async throws -> Void,
        onSuccess: (() -> Void)? = nil,
        onFailure: ((Error) -> Void)? = nil
    ) {
        self.roomJID = roomJID
        self.sendFunction = sendFunction
        self.onSuccess = onSuccess
        self.onFailure = onFailure
    }
}
