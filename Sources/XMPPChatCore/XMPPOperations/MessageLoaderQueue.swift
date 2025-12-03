//
//  MessageLoaderQueue.swift
//  XMPPChatCore
//
//  Auto-loads history for all rooms in batches when XMPP is idle
//  Based on useMessageLoaderQueue.tsx logic
//

import Foundation

@MainActor
public class MessageLoaderQueue {
    // Configuration constants (matching TypeScript defaults)
    private let batchSize: Int = 5  // Process 5 rooms at a time
    private let pageSize: Int = 10  // Load 10 messages per room per batch (matching TypeScript DEFAULT_PAGE_SIZE)
    private let pollInterval: TimeInterval = 1.0  // Check every 1 second when idle
    private let delayBetweenRooms: TimeInterval = 0.2  // 200ms delay between rooms
    private let targetMessageCount: Int = 20  // Target 20 messages per room (matching TypeScript max)
    
    private var processedRooms: Set<String> = []
    private var processingTimer: Timer?
    private var isProcessing: Bool = false
    
    private weak var client: XMPPClient?
    private var roomsProvider: (() -> [Room])?
    private var globalLoadingProvider: (() -> Bool)?
    private var loadingProvider: (() -> Bool)?
    
    public init(client: XMPPClient) {
        self.client = client
    }
    
    /// Set the rooms provider function
    public func setRoomsProvider(_ provider: @escaping () -> [Room]) {
        self.roomsProvider = provider
    }
    
    /// Set the global loading state provider
    public func setGlobalLoadingProvider(_ provider: @escaping () -> Bool) {
        self.globalLoadingProvider = provider
    }
    
    /// Set the loading state provider
    public func setLoadingProvider(_ provider: @escaping () -> Bool) {
        self.loadingProvider = provider
    }
    
    /// Start the auto-loading queue
    public func start() {
        stop() // Stop any existing timer
        
        // print("🔄 MessageLoaderQueue: Starting auto-load queue")
        
        // Reset processed rooms when starting
        processedRooms.removeAll()
        
        // Start polling
        processingTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.processQueue()
            }
        }
    }
    
    /// Stop the auto-loading queue
    public func stop() {
        processingTimer?.invalidate()
        processingTimer = nil
        isProcessing = false
        // print("⏹️ MessageLoaderQueue: Stopped auto-load queue")
    }
    
    /// Reset processed rooms (call when rooms list changes)
    public func reset() {
        processedRooms.removeAll()
        // print("🔄 MessageLoaderQueue: Reset processed rooms")
    }
    
    /// Check if room needs more messages (matching TypeScript roomHasMoreMessages)
    private func roomHasMoreMessages(_ room: Room, max: Int = 20) -> Bool {
        let messageCount = room.messages.count
        return messageCount < max
    }
    
    /// Check if room should be processed (matching TypeScript logic)
    private func shouldProcessRoom(_ room: Room) -> Bool {
        return roomHasMoreMessages(room, max: targetMessageCount) &&
               room.noMessages != true &&
               room.historyComplete != true
    }
    
    /// Process the queue - loads messages for rooms that need them (matching TypeScript logic)
    private func processQueue() async {
        // Don't process if already processing, client is not online, or if loading
        guard !isProcessing,
              let client = client,
              client.checkOnline() else {
            // print("⏭️ MessageLoaderQueue: Skipping queue process - isProcessing: \(isProcessing), client online: \(client?.checkOnline() ?? false)")
            return
        }
        
        // Check global loading and loading states (matching TypeScript)
        let isGlobalLoading = globalLoadingProvider?() ?? false
        let isLoading = loadingProvider?() ?? false
        
        if isGlobalLoading || isLoading {
            // print("⏭️ MessageLoaderQueue: Skipping queue process - globalLoading: \(isGlobalLoading), loading: \(isLoading)")
            return
        }
        
        // Get current rooms list
        guard let roomsProvider = roomsProvider else {
            // print("⚠️ MessageLoaderQueue: No rooms provider set")
            return
        }
        
        let allRooms = roomsProvider()
        // print("📋 MessageLoaderQueue: processQueue called - total rooms: \(allRooms.count)")
        
        // Filter unprocessed rooms (matching TypeScript: roomsList.filter(jid => !processedChats.current.has(jid)))
        let unprocessedRooms = allRooms.filter { room in
            !processedRooms.contains(room.jid)
        }
        
        // print("📋 MessageLoaderQueue: Unprocessed rooms: \(unprocessedRooms.count)")
        
        // Filter rooms that need messages
        let roomsNeedingMessages = unprocessedRooms.filter { room in
            shouldProcessRoom(room)
        }
        
        // print("📋 MessageLoaderQueue: Rooms needing messages: \(roomsNeedingMessages.count)")
        
        // If no rooms need processing, stop the timer (matching TypeScript)
        guard !unprocessedRooms.isEmpty else {
            if !processedRooms.isEmpty {
                // print("✅ MessageLoaderQueue: All rooms processed (\(processedRooms.count) rooms)")
            }
            stop()
            return
        }
        
        isProcessing = true
        
        // Process rooms in batches (matching TypeScript: for (let i = 0; i < unprocessed.length; i += batchSize))
        for i in stride(from: 0, to: unprocessedRooms.count, by: batchSize) {
            let endIndex = min(i + batchSize, unprocessedRooms.count)
            let batch = Array(unprocessedRooms[i..<endIndex])
            
            // print("📦 MessageLoaderQueue: Processing batch of \(batch.count) rooms (batch \(i/batchSize + 1))")
            
            // Process batch in parallel (matching TypeScript: await Promise.all(batch.map(...)))
            await withTaskGroup(of: Void.self) { group in
                for room in batch {
                    group.addTask { [weak self] in
                        await self?.loadMessagesForRoom(room)
                    }
                }
            }
        }
        
        isProcessing = false
        // print("✅ MessageLoaderQueue: Finished processing batch")
    }
    
    /// Load messages for a specific room (matching TypeScript logic)
    private func loadMessagesForRoom(_ room: Room) async {
        // Check if room should be processed (matching TypeScript conditions)
        let needsProcessing = shouldProcessRoom(room)
        let messageCount = room.messages.count
        let noMessages = room.noMessages ?? false
        let historyComplete = room.historyComplete ?? false
        
        // print("📊 MessageLoaderQueue: Room \(room.title) - messages: \(messageCount), noMessages: \(noMessages), historyComplete: \(historyComplete), needsProcessing: \(needsProcessing)")
        
        guard needsProcessing else {
            // Mark as processed even if we can't load
            processedRooms.insert(room.jid)
            // print("⏭️ MessageLoaderQueue: Skipping room \(room.title) (doesn't need processing)")
            return
        }
        
        guard let client = client,
              client.checkOnline() else {
            processedRooms.insert(room.jid)
            // print("⚠️ MessageLoaderQueue: Cannot load for room \(room.title) (client offline)")
            return
        }
        
        // print("📥 MessageLoaderQueue: Loading \(pageSize) messages for room: \(room.title) (\(room.jid))")
        
        // Send get-history request (matching TypeScript: await loadMoreMessages(jid, pageSize))
        // Note: TypeScript version doesn't pass before parameter, so we load from latest
        client.operations.sendGetHistory(
            chatJID: room.jid,
            max: pageSize,
            before: nil as Int64?
        )
        
        // Wait 200ms between rooms (matching TypeScript: await new Promise((res) => setTimeout(res, 200)))
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        // Mark as processed (matching TypeScript: processedChats.current.add(jid))
        processedRooms.insert(room.jid)
        
        // print("✅ MessageLoaderQueue: Sent get-history for room: \(room.title)")
    }
    
    /// Called when a room receives messages - check if it needs more
    /// Note: This is called automatically via NotificationCenter when messages are updated
    public func onRoomMessagesUpdated(roomJID: String, currentMessageCount: Int) {
        // If room still has less than target messages, remove from processed set
        // so it can be queued again in the next cycle
        if currentMessageCount < targetMessageCount {
            processedRooms.remove(roomJID)
            // print("🔄 MessageLoaderQueue: Room \(roomJID) still needs more messages (\(currentMessageCount)/\(targetMessageCount))")
        } else {
            processedRooms.insert(roomJID)
            // print("✅ MessageLoaderQueue: Room \(roomJID) has enough messages (\(currentMessageCount))")
        }
    }
    
    deinit {
        processingTimer?.invalidate()
        processingTimer = nil
    }
}

