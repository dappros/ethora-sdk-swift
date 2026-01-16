//
//  ChatRoomViewModel.swift
//  XMPPChatUI
//
//  ViewModel for Chat Room
//

import Foundation
import Combine
import XMPPChatCore

@MainActor
public class ChatRoomViewModel: ObservableObject, XMPPClientDelegate {
    @Published var room: Room
    @Published var messages: [Message] = []
    @Published var isTyping: Bool = false
    @Published var composingUsers: [String] = []
    @Published var isEditing: Bool = false
    @Published var editText: String?
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false  // For scroll-to-load
    @Published var isRefreshing: Bool = false  // For pull-to-refresh
    
    private let client: XMPPClient
    public let currentUserId: String
    
    // Helper to get current user's XMPP username from UserStore
    public var currentUserXmppUsername: String? {
        // UserStore might change, so we fetch it dynamically or listen to changes
        // Since we are MainActor, accessing UserStore.shared is safe
        return UserStore.shared.currentUser?.xmppUsername
    }
    
    private var cancellables = Set<AnyCancellable>()
    private var messagesLoaded: Bool = false // Track if messages have been loaded
    private var savedScrollPosition: String? // Track last scroll position (message ID)
    private var isFirstLoad: Bool = true // Track if this is the first time loading messages
    private var scrollPositionRestored: Bool = false // Track if we've already restored scroll position
    private var expectedMessageCount: Int = 0 // Track how many messages we expect to receive
    private var receivedMessageCount: Int = 0 // Track how many messages we've received in current load
    private var loadingStartTime: Date? // Track when loading started for timeout
    private var loadingMoreTask: Task<Void, Never>? // Task to handle loading more timeout/reset
    
    // Telegram-like scroll position maintenance
    private var scrollPositionBeforeLoad: (messageId: String, messageIndex: Int)? = nil
    private var messagesCountBeforeLoad: Int = 0
    private var lastMessageIdBeforeRefresh: String?
    
    // Callback to notify when room messages are updated
    public var onMessagesUpdated: ((Room) -> Void)?
    
    public init(room: Room, client: XMPPClient, currentUserId: String) {
        self.room = room
        self.client = client
        self.currentUserId = currentUserId
        
        // Load cached messages immediately
        loadCachedMessages()
        
        setupObservers()
    }
    
    private func setupObservers() {
        // Set up delegate to receive real-time messages
        // The XMPPClient delegate will call handleIncomingMessage for real-time messages
        // History messages are handled directly in loadMessages()
        client.delegate = self
        print("✅ ChatRoomViewModel: Set as XMPPClient delegate")
        
        // Observe composing (typing indicator) notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleComposingNotification(_:)),
            name: NSNotification.Name("XMPPComposingChanged"),
            object: nil
        )
        
        // Observe history complete notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHistoryCompleteNotification(_:)),
            name: NSNotification.Name("XMPPHistoryComplete"),
            object: nil
        )
    }
    
    @objc private func handleComposingNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let notificationRoomJID = userInfo["roomJID"] as? String,
              let composingList = userInfo["composingList"] as? [String],
              let isComposing = userInfo["isComposing"] as? Bool else {
            return
        }
        
        // Only handle composing for this room
        let normalizedNotificationRoom = notificationRoomJID.components(separatedBy: "/").first ?? notificationRoomJID
        let normalizedCurrentRoom = room.jid.components(separatedBy: "/").first ?? room.jid
        
        guard normalizedNotificationRoom == normalizedCurrentRoom else {
            return
        }
        
        print("⌨️ ChatRoomViewModel: Composing changed - isTyping: \(isComposing), users: \(composingList)")
        
        // Update UI on main thread
        Task { @MainActor in
            self.isTyping = isComposing
            self.composingUsers = composingList
        }
    }
    
    @objc private func handleHistoryCompleteNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let notificationRoomJID = userInfo["roomJID"] as? String,
              let historyComplete = userInfo["historyComplete"] as? Bool else {
            return
        }
        
        // Only handle for this room
        let normalizedNotificationRoom = notificationRoomJID.components(separatedBy: "/").first ?? notificationRoomJID
        let normalizedCurrentRoom = room.jid.components(separatedBy: "/").first ?? room.jid
        
        guard normalizedNotificationRoom == normalizedCurrentRoom else {
            return
        }
        
        print("📚 ChatRoomViewModel: History complete updated - complete: \(historyComplete)")
        
        // Update room's historyComplete flag
        Task { @MainActor in
            self.room.historyComplete = historyComplete
            if historyComplete {
                print("✅ ChatRoomViewModel: History is complete for room \(room.jid) - scroll-to-load disabled")
            }
        }
    }
    
    /// Set up XMPP client delegate to receive messages
    public func setupClientDelegate() {
        // Already set in setupObservers()
    }
    
    // MARK: - XMPPClientDelegate
    
    public func xmppClientDidConnect(_ client: XMPPClient) {
        print("📡 ChatRoomViewModel: XMPP client connected")
    }
    
    public func xmppClientDidDisconnect(_ client: XMPPClient) {
        print("📡 ChatRoomViewModel: XMPP client disconnected")
    }
    
    public func xmppClient(_ client: XMPPClient, didReceiveMessage message: Message) {
        // Handle the incoming message
        handleIncomingMessage(message)
    }
    
    public func xmppClient(_ client: XMPPClient, didReceiveStanza stanza: XMPPStanza) {
        // Stanza received - already handled by handleStanza
    }
    
    public func xmppClient(_ client: XMPPClient, didChangeStatus status: ConnectionStatus) {
        print("📡 ChatRoomViewModel: Connection status changed: \(status.rawValue)")
    }
    
    /// Load more messages (for scroll-to-load functionality)
    /// Similar to TypeScript loadMoreMessages function
    /// According to documentation: uses timestamp (Int64) for 'before' parameter
    public func loadMoreMessages(max: Int = 30, beforeTimestamp: Int64? = nil) {
        // Зберігаємо фактичну кількість повідомлень ПЕРЕД початком завантаження
        let actualMessageCountBeforeLoad = messages.count
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📜 loadMoreMessages CALLED")
        print("   max: \(max)")
        print("   beforeTimestamp param: \(beforeTimestamp?.description ?? "nil")")
        print("   isLoadingMore: \(isLoadingMore)")
        print("   historyComplete: \(room.historyComplete ?? false)")
        print("   📊 CURRENT MESSAGE COUNT: \(actualMessageCountBeforeLoad)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        // Логуємо перше і останнє повідомлення в масиві
        if let firstMessage = messages.first {
            print("📋 FIRST MESSAGE IN ARRAY:")
            print("   id: \(firstMessage.id)")
            print("   timestamp: \(firstMessage.timestamp?.description ?? "nil")")
            print("   date: \(firstMessage.date)")
            print("   body: \(firstMessage.body.prefix(50))...")
        } else {
            print("📋 FIRST MESSAGE: NONE (array is empty)")
        }
        
        if let lastMessage = messages.last {
            print("📋 LAST MESSAGE IN ARRAY:")
            print("   id: \(lastMessage.id)")
            print("   timestamp: \(lastMessage.timestamp?.description ?? "nil")")
            print("   date: \(lastMessage.date)")
            print("   body: \(lastMessage.body.prefix(50))...")
        } else {
            print("📋 LAST MESSAGE: NONE (array is empty)")
        }
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        // Check if already loading or history is complete
        guard !isLoadingMore else {
            print("⚠️ loadMoreMessages: SKIPPED - already loading")
            return
        }
        guard room.historyComplete != true else {
            print("⚠️ loadMoreMessages: SKIPPED - history complete")
            return
        }
        
        // According to TypeScript: use message ID (converted to number) for 'before' parameter
        // TypeScript: loadMoreMessages(firstMessage.roomJid, 30, Number(firstMessageId))
        // Find oldest message and use its ID
        let beforeMessageId: Int64? = {
            // If ID provided directly, use it
            if let beforeTimestamp = beforeTimestamp {
                return beforeTimestamp
            }
            
            // Find the oldest message (skip delimiter-new if present)
            let firstMessage = messages.first(where: { $0.id != "delimiter-new" }) ?? messages.first
            
            guard let message = firstMessage else {
                return nil
            }
            
            // Use message.id converted to Int64 (matching TypeScript: Number(firstMessageId))
            if let idAsNumber = Int64(message.id) {
                return idAsNumber
            }
            
            // Fallback: if ID is not numeric, try to use timestamp
            if let timestamp = message.timestamp {
                return timestamp
            }
            
            // Last resort: convert date to timestamp
            return Int64(message.date.timeIntervalSince1970 * 1000)
        }()
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🎯 BEFORE MESSAGE ID TO SEND: \(beforeMessageId?.description ?? "nil")")
        if let firstMsg = messages.first(where: { $0.id != "delimiter-new" }) ?? messages.first {
            print("   Oldest message:")
            print("      id: \(firstMsg.id)")
            print("      id as Int64: \(Int64(firstMsg.id)?.description ?? "nil")")
            print("      timestamp: \(firstMsg.timestamp?.description ?? "nil")")
            print("      date: \(firstMsg.date)")
            print("      body: \(firstMsg.body.prefix(50))...")
        }
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        // Save scroll position before loading (Telegram-like behavior)
        // Використовуємо фактичну кількість повідомлень, збережену на початку функції
        if let firstMessage = messages.first {
            scrollPositionBeforeLoad = (messageId: firstMessage.id, messageIndex: 0)
            messagesCountBeforeLoad = actualMessageCountBeforeLoad
            print("📌 Saved scroll position: messageId=\(firstMessage.id), index=0, count=\(messagesCountBeforeLoad) (actual count before load)")
        }
        
        isLoadingMore = true
        
        // Send get-history request with message ID (matching TypeScript: Number(firstMessageId))
        client.operations.sendGetHistory(
            chatJID: room.jid,
            max: max,
            before: beforeMessageId
        )
        
        // Set timeout to reset loading state (safety timeout)
        loadingMoreTask?.cancel()
        loadingMoreTask = Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds safety timeout
            print("⏰ loadMoreMessages: Timeout reached (30s), resetting isLoadingMore")
            isLoadingMore = false
            scrollPositionBeforeLoad = nil
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
    
    /// Pull to refresh - reload latest messages
    /// Завантажує останні повідомлення (без параметра before)
    public func refreshMessages() {
        print("🔄 Pull to refresh triggered")
        isLoadingMore = false
        isRefreshing = true
        loadingMoreTask?.cancel()
        
        // Зберігаємо ID останнього повідомлення перед оновленням
        lastMessageIdBeforeRefresh = messages.last?.id
        
        // Send get-history without before parameter to get latest messages
        // Це завантажить останні 30 повідомлень
        client.operations.sendGetHistory(
            chatJID: room.jid,
            max: 30,
            before: nil as Int64?
        )
        
        print("📥 Запит на завантаження останніх повідомлень відправлено (без before)")
        
        // Автоматично скидаємо прапорець через 3 секунди, якщо повідомлення не прийшли
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 секунди
            if isRefreshing {
                isRefreshing = false
                print("⏱️ Refresh timeout - скидаємо прапорець")
            }
        }
    }
    
    /// Load message history from XMPP
    /// Sends get-history MAM query - messages will be received through onMessageHistory handler in StanzaHandlers
    public func loadMessages(max: Int = 30, before: Int64? = nil, forceReload: Bool = false) {
        // If messages are already loaded and we're not forcing a reload, just ensure they're displayed
        if messagesLoaded && !forceReload && !messages.isEmpty {
            print("📋 ChatRoomViewModel: Messages already loaded (\(messages.count) messages), skipping reload")
            // Trigger a refresh to ensure UI updates
            objectWillChange.send()
            return
        }
        
        print("📋 ChatRoomViewModel: loadMessages called")
        print("   Room: \(room.jid), max: \(max), before: \(before?.description ?? "nil")")
        
        // Check if client is online before sending query
        guard client.checkOnline() else {
            print("⚠️ Client is not online, cannot send get-history query. Status: \(client.status)")
            // Wait a bit and retry if client becomes online
            Task {
                // Wait up to 5 seconds for client to come online
                for _ in 0..<10 {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    if client.checkOnline() {
                        print("✅ Client is now online, sending get-history query...")
                        loadMessages(max: max, before: before, forceReload: forceReload)
                        return
                    }
                }
                print("❌ Client did not come online within 5 seconds")
            }
            return
        }
        
        // Check if we have cached messages - if so, show them immediately and load in background
        if let cachedMessages = MessageCache.shared.loadMessages(forRoomJID: room.jid), !forceReload {
            messages = cachedMessages
            room.messages = cachedMessages
            messagesLoaded = true
            print("📂 ChatRoomViewModel: Using \(cachedMessages.count) cached messages, loading fresh in background")
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
        
        print("✅ Get-history query sent. Expecting \(max) messages.")
        
        // Set a timeout to hide loader if messages don't arrive within 10 seconds
        Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            if isLoading {
                print("⏱️ Loading timeout reached. Hiding loader.")
        isLoading = false
                messagesLoaded = true
            }
        }
    }
    
    /// Load cached messages from disk
    private func loadCachedMessages() {
        if let cachedMessages = MessageCache.shared.loadMessages(forRoomJID: room.jid) {
            messages = cachedMessages
            room.messages = cachedMessages
            messagesLoaded = true
            print("📂 ChatRoomViewModel: Loaded \(cachedMessages.count) cached messages for room: \(room.jid)")
        }
    }
    
    /// Called when view appears - ensures messages are displayed
    public func onViewAppeared() {
        // If messages are already loaded, just ensure they're displayed
        if messagesLoaded && !messages.isEmpty {
            print("📋 ChatRoomViewModel: View appeared, displaying \(messages.count) existing messages")
            // Trigger a refresh to ensure UI updates
            objectWillChange.send()
        } else {
            // Load messages if not already loaded
            loadMessages()
        }
    }
    
    /// Save the current scroll position (called when leaving the chat)
    public func saveScrollPosition(messageId: String?) {
        // Use the provided message ID or last message as fallback
        // We don't track visible messages during scroll to avoid performance issues
        savedScrollPosition = messageId ?? messages.last?.id
        isFirstLoad = false
        scrollPositionRestored = false // Reset for next time
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
        if isFirstLoad {
            // On first load, return nil to scroll to bottom
            return nil
        }
        // On subsequent loads, return saved position
        return savedScrollPosition
    }
    
    /// Check if we should scroll to bottom (first load)
    public func shouldScrollToBottom() -> Bool {
        return isFirstLoad
    }
    
    public func sendMessage(_ text: String) {
        guard !text.isEmpty else { return }
        
        print("🔥🔥🔥 CHATROOMVIEWMODEL.SENDMESSAGE CALLED 🔥🔥🔥")
        print("📤 Sending message: \(text)")
        
        // Get current user info from UserStore
        let user = UserStore.shared.currentUser
        let firstName = user?.firstName ?? "User"
        let lastName = user?.lastName ?? "Name"
        let walletAddress = user?.walletAddress ?? ""
        let photo = user?.profileImage ?? ""
        
        print("👤 User info: \(firstName) \(lastName)")
        
        client.operations.sendTextMessage(
            roomJID: room.jid,
            firstName: firstName,
            lastName: lastName,
            photo: photo,
            walletAddress: walletAddress,
            userMessage: text
        )
        
        // Add message optimistically to UI (will be confirmed when received from server)
        let optimisticMessage = Message(
            id: "pending-\(Int64(Date().timeIntervalSince1970 * 1000))",
            user: User(
                id: currentUserId,
                name: "\(firstName) \(lastName)",
                firstName: firstName,
                lastName: lastName,
                profileImage: photo,
                xmppUsername: currentUserId
            ),
            date: Date(),
            body: text,
            roomJid: room.jid,
            pending: true,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000)
        )
        
        messages.append(optimisticMessage)
    }
    
    /// Handle incoming real-time message
    /// Matches TypeScript: store.dispatch(addRoomMessage({ roomJID, message }))
    public func handleIncomingMessage(_ message: Message) {
        // Match TypeScript: Only add if message has body
        // if (!message?.body) return;
        guard !message.body.isEmpty else {
            return
        }
        
        // Match TypeScript: Check if room exists
        // const roomExist = !!state?.rooms[roomJID];
        // if (!roomExist) { return; }
        // For Swift, we check if the message is for this room
        // Extract bare JID (without resource) for comparison
        // The roomJID passed from StanzaHandlers is already the bare JID
        let messageRoomBareJID = message.roomJid.components(separatedBy: "/").first ?? message.roomJid
        let currentRoomBareJID = room.jid.components(separatedBy: "/").first ?? room.jid
        
        guard messageRoomBareJID == currentRoomBareJID else {
            // Message is for a different room, ignore it
            print("⚠️ handleIncomingMessage: Message is for different room - SKIPPING")
            print("   Message room: \(messageRoomBareJID)")
            print("   Current room: \(currentRoomBareJID)")
            return
        }
        
        print("✅ handleIncomingMessage: Room matches, processing message")
        
        // Match TypeScript: Check for existing message (avoid duplicates)
        // const existingIndex = roomMessages.findIndex(...)
        if let existingIndex = messages.firstIndex(where: { msg in
            msg.id == message.id ||
            (message.xmppId != nil && msg.id == message.xmppId) ||
            (msg.xmppId != nil && msg.xmppId == message.id)
        }) {
            // Match TypeScript: Update existing message instead of adding duplicate
            // roomMessages[existingIndex] = deepMerge({ ...roomMessages[existingIndex] }, { ...message, pending: false });
            print("⚠️ handleIncomingMessage: Message already exists at index \(existingIndex) - UPDATING")
            messages[existingIndex] = message
            return
        }
        
        print("✅ handleIncomingMessage: Message is new, will be added")
        
        // Remove any pending message with same content (optimistic update confirmation)
        if let pendingIndex = messages.firstIndex(where: { $0.pending == true && $0.body == message.body }) {
            messages.remove(at: pendingIndex)
        }
        
        // Match TypeScript: Add message with delimiter logic
        // Check if we need to insert a "New Messages" delimiter
        let shouldInsertDelimiter = !messages.contains(where: { $0.id == "delimiter-new" }) &&
                                    room.lastViewedTimestamp != nil &&
                                    room.lastViewedTimestamp! > 0 &&
                                    (message.timestamp ?? 0) > room.lastViewedTimestamp!
        
        if shouldInsertDelimiter {
            // Find the index where the delimiter should go
            if let delimiterIndex = messages.firstIndex(where: { ($0.timestamp ?? 0) > room.lastViewedTimestamp! }) {
                // Insert delimiter message
                let delimiterMessage = Message(
                    id: "delimiter-new",
                    user: User(
                        id: "system",
                        name: "System",
                        firstName: nil,
                        lastName: nil,
                        profileImage: nil,
                        xmppUsername: "system"
                    ),
                    date: Date(),
                    body: "New Messages",
                    roomJid: room.jid,
                    timestamp: room.lastViewedTimestamp
                )
                messages.insert(delimiterMessage, at: delimiterIndex)
            }
        }
        
        // Add the actual message
        let messageCountBeforeAdd = messages.count
        messages.append(message)
        
        print("📊 Message added to array:")
        print("   Count before: \(messageCountBeforeAdd)")
        print("   Count after: \(messages.count)")
        
        // Match TypeScript: Sort by timestamp (messages should be in chronological order)
        messages.sort { msg1, msg2 in
            let ts1 = msg1.timestamp ?? 0
            let ts2 = msg2.timestamp ?? 0
            return ts1 < ts2
        }
        
        print("📊 Messages sorted, final count: \(messages.count)")
        
        // Update room's messages array
        room.messages = messages
        // Update the published room property to trigger UI updates
        self.room = room
        
        // Save messages to cache
        MessageCache.shared.saveMessages(messages, forRoomJID: room.jid)
        
        // Якщо це pull-to-refresh і з'явилося нове повідомлення, скидаємо прапорець
        if isRefreshing, let lastMessageId = messages.last?.id, lastMessageId != lastMessageIdBeforeRefresh {
            isRefreshing = false
            lastMessageIdBeforeRefresh = nil
            print("✅ Pull-to-refresh завершено: нові повідомлення завантажено")
        }
        
        print("✅ Message with body '\(message.body.prefix(30))...' added to room with id '\(room.jid)'")
        print("   Final messages count: \(messages.count)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        // Track received messages for initial load
        // Only count if we're currently loading and this is a history message (not real-time)
        if isLoading && expectedMessageCount > 0 {
            receivedMessageCount += 1
            print("📊 Received \(receivedMessageCount)/\(expectedMessageCount) messages")
            
            // Check if we've received all expected messages
            // Also check if we've received at least the expected count or if 3 seconds have passed
            let timeSinceStart = loadingStartTime.map { Date().timeIntervalSince($0) } ?? 0
            
            if receivedMessageCount >= expectedMessageCount || timeSinceStart >= 3.0 {
                // All messages received or timeout reached, hide loader
                isLoading = false
                messagesLoaded = true
                loadingStartTime = nil
                print("✅ Loading complete. Received \(receivedMessageCount) messages. Hiding loader.")
            }
        } else {
            // If we are loading more (scrolling up), debounced reset of isLoadingMore
            if isLoadingMore {
                loadingMoreTask?.cancel()
                loadingMoreTask = Task {
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second silence = batch done
                    isLoadingMore = false
                    
                    let currentCount = messages.count
                    let loadedCount = currentCount - messagesCountBeforeLoad
                    
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    print("📜 ChatRoomViewModel: Batch load complete (debounced)")
                    print("   📊 Message count before load: \(messagesCountBeforeLoad)")
                    print("   📊 Message count after load: \(currentCount)")
                    print("   📊 Messages loaded: \(loadedCount)")
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    
                    // Post notification to reset scroll trigger and restore position
                    NotificationCenter.default.post(
                        name: NSNotification.Name("MessagesLoaded"),
                        object: nil,
                        userInfo: [
                            "oldCount": messagesCountBeforeLoad,
                            "newCount": currentCount,
                            "loadedCount": loadedCount
                        ]
                    )
                }
            }
            
            // Mark that messages have been loaded once we receive at least one message
            if !messagesLoaded {
                messagesLoaded = true
            }
        }
        
        // Notify callback that room was updated
        onMessagesUpdated?(room)
        
        // Notify message loader queue about updated message count
        // This allows the queue to continue loading if room still needs more messages
        NotificationCenter.default.post(
            name: NSNotification.Name("RoomMessagesUpdated"),
            object: nil,
            userInfo: [
                "roomJID": room.jid,
                "messageCount": messages.count
            ]
        )
    }
    
    public func sendMedia(data: Data, type: String) {
        guard let user = UserStore.shared.currentUser else {
            print("❌ ChatRoomViewModel.sendMedia: No current user")
            return
        }
        
        // Generate unique message ID
        let messageId = "send-media-message-\(Int64(Date().timeIntervalSince1970 * 1000))"
        
        // Extract file name from type or use default
        let fileName = "media_\(Int64(Date().timeIntervalSince1970 * 1000))"
        let fileExtension: String
        if type.starts(with: "image/") {
            fileExtension = type.contains("png") ? "png" : "jpg"
        } else if type.starts(with: "video/") {
            fileExtension = "mp4"
        } else if type.contains("pdf") {
            fileExtension = "pdf"
        } else {
            fileExtension = "bin"
        }
        let fullFileName = "\(fileName).\(fileExtension)"
        
        Task {
            do {
                // Upload file to server
                guard let token = UserStore.shared.token else {
                    print("❌ ChatRoomViewModel.sendMedia: No authentication token")
                    return
                }
                
                print("📤 ChatRoomViewModel.sendMedia: Uploading file \(fullFileName) (\(data.count) bytes)")
                let uploadResponse = try await AuthAPI.uploadFile(
                    fileData: data,
                    fileName: fullFileName,
                    mimeType: type,
                    token: token
                )
                
                guard let uploadResult = uploadResponse.results.first else {
                    print("❌ ChatRoomViewModel.sendMedia: No upload result")
                    return
                }
                
                print("✅ ChatRoomViewModel.sendMedia: File uploaded successfully")
                print("   Location: \(uploadResult.location)")
                print("   ID: \(uploadResult._id)")
                
                // Create media message data
                let mediaData = MediaMessageData(
                    firstName: user.firstName ?? "",
                    lastName: user.lastName ?? "",
                    walletAddress: user.walletAddress ?? "",
                    chatName: room.title,
                    createdAt: uploadResult.createdAt,
                    fileName: uploadResult.filename,
                    userId: uploadResult.userId ?? user.id,
                    isVisible: uploadResult.isVisible ?? true,
                    userAvatar: user.profileImage,
                    expiresAt: uploadResult.expiresAt,
                    location: uploadResult.location,
                    locationPreview: uploadResult.locationPreview,
                    mimetype: uploadResult.mimetype,
                    originalName: uploadResult.originalname ?? uploadResult.filename,
                    ownerKey: uploadResult.ownerKey,
                    size: uploadResult.size,
                    duration: uploadResult.duration,
                    updatedAt: uploadResult.updatedAt,
                    attachmentId: uploadResult._id,
                    roomJid: room.jid
                )
                
                // Send media message via XMPP
                client.operations.sendMediaMessage(
                    roomJID: room.jid,
                    data: mediaData,
                    id: messageId
                )
                
                print("✅ ChatRoomViewModel.sendMedia: Media message sent via XMPP")
                
            } catch {
                print("❌ ChatRoomViewModel.sendMedia: Error - \(error.localizedDescription)")
            }
        }
    }
    
    public func editMessage(_ messageId: String, newText: String) {
        client.operations.editMessage(
            chatId: room.jid,
            messageId: messageId,
            text: newText
        )
    }
    
    public func resendMessage(_ message: Message) {
        // Check if message is a media message
        if message.isMediafile == "true" || message.mimetype != nil {
            // Resend as media message
            if let location = message.location,
               let url = URL(string: location) {
                Task {
                    do {
                        let data = try Data(contentsOf: url)
                        let mimeType = message.mimetype ?? "application/octet-stream"
                        sendMedia(data: data, type: mimeType)
                    } catch {
                        print("❌ ChatRoomViewModel.resendMessage: Error loading media - \(error.localizedDescription)")
                    }
                }
            }
        } else {
            // Resend as text message
            sendMessage(message.body)
        }
    }
    
    public func deleteMessage(_ messageId: String) {
        client.operations.deleteMessage(room: room.jid, msgId: messageId)
    }
    
    public func cancelEdit() {
        isEditing = false
        editText = nil
    }
    
    public func startTyping() {
        // Send typing indicator
    }
    
    public func stopTyping() {
        // Send stop typing indicator
    }
}

