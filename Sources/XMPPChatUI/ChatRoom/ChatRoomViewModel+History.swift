//
//  ChatRoomViewModel+History.swift
//  XMPPChatUI
//

import Foundation

extension ChatRoomViewModel {
    /// Load more messages (internal transport helper for history loading)
    /// Similar to TypeScript loadMoreMessages function
    /// According to documentation: uses timestamp (Int64) for 'before' parameter
    /// NOTE: This is an internal transport helper. UI components should use MessageListViewModel.fetchHistory() instead.
    /// This method is kept public for backward compatibility with ChatRoomView, but new code should use MessageListViewModel.
    public func loadMoreMessages(max: Int = 30, beforeTimestamp: Int64? = nil) {
        print("📜 ChatRoomViewModel.loadMoreMessages: called")
        print("   Room: \(room.jid)")
        print("   max: \(max)")
        print("   beforeTimestamp: \(beforeTimestamp?.description ?? "nil")")
        print("   isLoadingMore: \(isLoadingMore)")
        print("   historyComplete: \(room.historyComplete ?? false)")
        print("   current messages.count: \(messages.count)")
        
        // Зберігаємо фактичну кількість повідомлень ПЕРЕД початком завантаження
        let actualMessageCountBeforeLoad = messages.count
        
        // Check if already loading or history is complete
        guard !isLoadingMore else {
            print("⚠️ ChatRoomViewModel.loadMoreMessages: SKIPPED - already loading (isLoadingMore == true)")
            return
        }
        guard room.historyComplete != true else {
            print("⚠️ ChatRoomViewModel.loadMoreMessages: SKIPPED - history complete == true")
            return
        }
        
        // Match web version EXACTLY: loadMoreMessages(firstMessage.roomJid, 30, Number(firstMessageId))
        // The 'before' parameter should be the message ID converted to number using Number()
        // In TypeScript: Number(firstMessageId) converts string ID to number
        
        // Use the beforeTimestamp passed from ChatRoomView (which already does Number(firstMessageId) conversion)
        // If not provided, find the first message and convert its ID
        let beforeMessageId: Int64? = {
            // If beforeTimestamp was provided, use it (it's already converted from message.id)
            if let before = beforeTimestamp {
                return before
            }
            
            // Find the oldest message (skip delimiter-new if present) - matches web version
            let firstMessage = messages.first(where: { $0.id != "delimiter-new" }) ?? messages.first
            
            guard let message = firstMessage else {
                return nil
            }
            
            // Match TypeScript: Number(firstMessageId) - try to convert message.id to number
            if let idAsNumber = Int64(message.id) {
                return idAsNumber
            }
            
            // If message.id is not numeric (e.g., UUID), try timestamp
            if let timestamp = message.timestamp {
                return timestamp
            }
            
            // Last resort: convert date to timestamp (milliseconds)
            let dateTimestamp = Int64(message.date.timeIntervalSince1970 * 1000)
            return dateTimestamp
        }()
        
        guard let before = beforeMessageId else {
            print("❌ ChatRoomViewModel.loadMoreMessages: Could not determine 'before' parameter, aborting history request")
            return
        }
        
        // Save scroll position before loading (Telegram-like behavior)
        saveScrollPositionBeforeLoad()
        
        // Use pageSize from config if available, otherwise use provided max
        let effectiveMax = max > 0 ? max : pageSize
        
        isLoadingMore = true
        historyLoadReceivedCount = 0 // Reset counter for this history load
        historyLoadStartTime = Date() // Track when this load started
        print("🚀 ChatRoomViewModel.loadMoreMessages: sending get-history request")
        print("   effectiveMax: \(effectiveMax)")
        print("   before (final): \(before)")
        
        // Send get-history request - matches TypeScript: loadMoreMessages(roomJid, pageSize, Number(firstMessageId))
        // The 'before' parameter is the message ID as a number
        client.operations.sendGetHistory(
            chatJID: room.jid,
            max: effectiveMax,
            before: before
        )
        
        print("✅ ChatRoomViewModel.loadMoreMessages: get-history query sent with before=\(before)")
        
        // Set timeout to reset loading state (safety timeout)
        loadingMoreTask?.cancel()
        loadingMoreTask = Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds safety timeout
            print("⏰ ChatRoomViewModel.loadMoreMessages: Timeout reached (30s), resetting isLoadingMore and scrollPositionBeforeLoad")
            isLoadingMore = false
            scrollPositionBeforeLoad = nil
            historyLoadReceivedCount = 0
            historyLoadStartTime = nil
        }
    }
    
    /// Save scroll position before loading more messages
    public func saveScrollPositionBeforeLoad() {
        if let firstMessage = messages.first(where: { $0.id != "delimiter-new" }) ?? messages.first {
            scrollPositionBeforeLoad = (messageId: firstMessage.id, messageIndex: 0)
            messagesCountBeforeLoad = messages.count
        }
    }
    
    /// Get scroll position info for maintaining position after loading
    public func getScrollPositionInfo() -> (messageId: String, messageIndex: Int, oldCount: Int)? {
        guard let saved = scrollPositionBeforeLoad else { return nil }
        return (saved.messageId, saved.messageIndex, messagesCountBeforeLoad)
    }
    
    /// Clear scroll position info after it's been restored
    public func clearScrollPositionInfo() {
        scrollPositionBeforeLoad = nil
        messagesCountBeforeLoad = 0
    }
    
    /// Pull to refresh - reload latest messages (internal/legacy)
    /// Завантажує останні повідомлення (без параметра before)
    /// Also clears errors and retries loading if there was an error
    /// NOTE: Pull-to-refresh has been removed from the UI. This method is kept for explicit retry flows only.
    public func refreshMessages() {
        // Clear any previous errors
        loadError = nil
        
        isLoadingMore = false
        isRefreshing = true
        loadingMoreTask?.cancel()
        
        // Зберігаємо ID останнього повідомлення перед оновленням
        lastMessageIdBeforeRefresh = messages.last?.id
        let messageCountBeforeRefresh = messages.count
        
        // Check if client is online
        guard client.checkOnline() else {
            loadError = "Client is not online. Please check your connection."
            isRefreshing = false
            return
        }
        
        // Actually reload messages - this will send get-history query
        // Use forceReload to ensure we get fresh messages even if cached
        loadMessages(max: pageSize, before: nil, forceReload: true)
        
        // Автоматично скидаємо прапорець через 5 секунд, якщо повідомлення не прийшли
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 секунд
            if isRefreshing {
                isRefreshing = false
                // Set error if still refreshing after timeout and no new messages
                let messageCountAfterRefresh = messages.count
                if messageCountAfterRefresh == messageCountBeforeRefresh || messages.isEmpty {
                    loadError = "Failed to load new messages. Pull down to retry."
                }
            }
        }
    }
    
    /// Load message history from XMPP
    /// Sends get-history MAM query - messages will be received through onMessageHistory handler in StanzaHandlers
    public func loadMessages(max: Int = 30, before: Int64? = nil, forceReload: Bool = false) {
        // If messages are already loaded and we're not forcing a reload, just ensure they're displayed
        if messagesLoaded && !forceReload && !messages.isEmpty {
            // Trigger a refresh to ensure UI updates
            objectWillChange.send()
            return
        }
        
        // Clear any previous errors
        loadError = nil
        
        // Check if client is fully connected (online AND presences ready)
        // This prevents sending queries before the XMPP connection is fully established
        guard client.isFullyConnected() else {
            let isOnline = client.checkOnline()
            let presencesReady = client.presencesReady
            
            // Show cached messages while waiting
            if let cachedMessages = MessageCache.shared.loadMessages(forRoomJID: room.jid) {
                let sortedMessages = cachedMessages.sorted { ($0.timestamp ?? 0) < ($1.timestamp ?? 0) }
                messages = sortedMessages
                room.messages = sortedMessages
                messagesLoaded = true
            }
            
            isLoading = false
            
            // Wait for client to become fully connected with exponential backoff
            Task {
                var attempts = 0
                let maxAttempts = 10
                
                while attempts < maxAttempts {
                    attempts += 1
                    let delay = min(Double(attempts) * 0.5, 3.0) // 0.5s, 1s, 1.5s, ... up to 3s
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    
                    if client.isFullyConnected() {
                        loadError = nil
                        loadMessages(max: max, before: before, forceReload: forceReload)
                        return
                    }
                }
                
                loadError = "Connection timeout. Pull down to retry."
            }
            return
        }
        
        // Check if we have cached messages - if so, show them immediately and load in background
        if let cachedMessages = MessageCache.shared.loadMessages(forRoomJID: room.jid), !forceReload {
            let sortedMessages = cachedMessages.sorted { ($0.timestamp ?? 0) < ($1.timestamp ?? 0) }
            messages = sortedMessages
            room.messages = sortedMessages
            messagesLoaded = true
            // Don't show loader if we have cached messages
            isLoading = false
        } else {
            // Mark that we're loading messages
            messagesLoaded = false
            isLoading = true // Show loader
        }
        
        expectedMessageCount = max
        receivedMessageCount = 0
        loadingStartTime = Date()
        
        // Send get-history MAM query (even if we have cache, to get any new messages)
        // Messages will be handled automatically by StanzaHandlers.onMessageHistory
        client.operations.sendGetHistory(
            chatJID: room.jid,
            max: max,
            before: before
        )
        
        // Set a timeout to hide loader if messages don't arrive within 10 seconds
        Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            if isLoading {
                isLoading = false
                messagesLoaded = true
                // Set error if no messages were received
                if messages.isEmpty {
                    loadError = "Failed to load messages. Pull down to retry."
                }
            }
        }
    }
    
    /// Load cached messages from disk
    internal func loadCachedMessages() {
        if let cachedMessages = MessageCache.shared.loadMessages(forRoomJID: room.jid) {
            let sortedMessages = cachedMessages.sorted { ($0.timestamp ?? 0) < ($1.timestamp ?? 0) }
            messages = sortedMessages
            room.messages = sortedMessages
            messagesLoaded = true
        }
    }
    
    /// Called when view appears - ensures messages are displayed
    public func onViewAppeared() {
        // Always show newest messages when entering chat
        isFirstLoad = true
        savedScrollPosition = nil
        scrollPositionRestored = false
        
        // Guard: Don't load if already loading to prevent multiple simultaneous requests
        guard !isLoading && !isLoadingMore else {
            return
        }
        
        // If messages are already loaded, just ensure they're displayed
        if messagesLoaded && !messages.isEmpty {
            // Trigger a refresh to ensure UI updates
            objectWillChange.send()
        } else {
            // Wait a bit to ensure XMPP connection is stable before loading
            Task { @MainActor in
                // Small delay to ensure connection is stable
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                
                // Check connection again before loading
                guard client.checkOnline() else {
                    return
                }
                
                // Load messages if not already loaded
                loadMessages()
            }
        }
    }
    
    /// Mark room as active and clear unread state
    public func markRoomActive() {
        let roomJIDKey = room.jid.components(separatedBy: "/").first ?? room.jid
        RoomStore.shared.setActiveRoom(roomJIDKey)
        
        if messages.contains(where: { $0.id == "delimiter-new" }) {
            messages.removeAll { $0.id == "delimiter-new" }
            room.messages = messages
            RoomStore.shared.setRoomMessages(roomJID: roomJIDKey, messages: messages)
        }
        
        room.lastViewedTimestamp = 0
        room.unreadMessages = 0
        var updates = PartialRoomUpdate()
        updates.lastViewedTimestamp = 0
        updates.unreadMessages = 0
        RoomStore.shared.updateRoom(jid: roomJIDKey, updates: updates)
        
        // Update cache LRU metadata so active rooms are kept hot
        MessageCache.shared.markRoomAccessed(roomJID: room.jid)
        
        onMessagesUpdated?(room)
    }
    
    /// Mark room as inactive and store last viewed timestamp
    public func markRoomInactive() {
        let roomJIDKey = room.jid.components(separatedBy: "/").first ?? room.jid
        RoomStore.shared.setActiveRoom(nil)
        
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        room.lastViewedTimestamp = timestamp
        room.unreadMessages = 0
        var updates = PartialRoomUpdate()
        updates.lastViewedTimestamp = timestamp
        updates.unreadMessages = 0
        RoomStore.shared.updateRoom(jid: roomJIDKey, updates: updates)
        
        // Run lightweight cache maintenance when leaving a room
        MessageCache.shared.cleanupIfNeeded()
        
        onMessagesUpdated?(room)
    }
    
    /// Save the current scroll position (called when leaving the chat)
    public func saveScrollPosition(messageId: String?) {
        // Intentionally no-op: we always show newest messages on next open
        savedScrollPosition = nil
        scrollPositionRestored = false
    }
    
    /// Mark that scroll position has been restored (to avoid multiple restorations)
    public func markScrollPositionRestored() {
        scrollPositionRestored = true
    }
    
    /// Check if scroll position has been restored (to avoid multiple restorations)
    public var hasRestoredScrollPosition: Bool {
        return scrollPositionRestored
    }
    
    /// Get the saved scroll position (returns nil on first load to scroll to bottom)
    public func getScrollPosition() -> String? {
        return nil
    }
    
    /// Check if we should scroll to bottom (first load)
    public func shouldScrollToBottom() -> Bool {
        if isFirstLoad {
            isFirstLoad = false
            return true
        }
        return false
    }
}
