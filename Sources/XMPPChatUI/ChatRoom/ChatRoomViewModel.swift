//
//  ChatRoomViewModel.swift
//  XMPPChatUI
//
//  ViewModel for Chat Room
//

import Foundation
import Combine
import XMPPChatCore
#if os(iOS)
import UIKit
#endif

@MainActor
public class ChatRoomViewModel: ObservableObject, XMPPClientDelegate {
    @Published var room: Room
    @Published var messages: [Message] = []
    @Published var isTyping: Bool = false
    @Published var composingUsers: [String] = []
    @Published var isEditing: Bool = false
    @Published var editText: String?
    @Published var editMessageId: String?
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false  // For scroll-to-load
    @Published var isRefreshing: Bool = false  // For pull-to-refresh
    @Published var loadError: String? = nil  // Error message when loading fails
    
    private let client: XMPPClient
    public let currentUserId: String
    public let config: ChatConfig?
    
    /// Configurable page size for history loading (default: 30)
    public var pageSize: Int = 30
    
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
    private var historyLoadReceivedCount: Int = 0 // Track messages received during history load (including duplicates)
    private var historyLoadStartTime: Date? // Track when history load started
    
    // Telegram-like scroll position maintenance
    private var scrollPositionBeforeLoad: (messageId: String, messageIndex: Int)? = nil
    private var messagesCountBeforeLoad: Int = 0
    private var lastMessageIdBeforeRefresh: String?
    
    // Callback to notify when room messages are updated
    public var onMessagesUpdated: ((Room) -> Void)?
    
    public init(room: Room, client: XMPPClient, currentUserId: String, config: ChatConfig? = nil) {
        self.room = room
        self.client = client
        self.currentUserId = currentUserId
        self.config = config
        
        // Load cached messages immediately
        loadCachedMessages()
        
        setupObservers()
    }
    
    private func setupObservers() {
        // DON'T set as delegate - use NotificationCenter instead to avoid overwriting other chat rooms' delegates
        // The XMPPClient should use NotificationCenter for broadcasting messages to all interested parties
        // Only set delegate if no other delegate is set (to avoid conflicts)
        // For now, we'll use NotificationCenter for all message handling
        // client.delegate = self  // REMOVED: Causes conflicts when multiple chat rooms are open
        //print("✅ ChatRoomViewModel: Using NotificationCenter for message handling (no delegate conflict)")
        
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
        
        // Observe reaction notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleReactionNotification(_:)),
            name: NSNotification.Name("XMPPReactionReceived"),
            object: nil
        )
        
        // Observe delete message notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeleteNotification(_:)),
            name: NSNotification.Name("XMPPMessageDeleted"),
            object: nil
        )
        
        // Observe edit message notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEditNotification(_:)),
            name: NSNotification.Name("XMPPMessageEdited"),
            object: nil
        )
        
        // Observe incoming real-time messages via NotificationCenter (instead of delegate)
        // This allows multiple chat rooms to receive messages without conflicts
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleIncomingMessageNotification(_:)),
            name: NSNotification.Name("XMPPMessageReceived"),
            object: nil
        )
        
        // Observe history load failures for retry logic
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHistoryLoadFailedNotification(_:)),
            name: NSNotification.Name("XMPPHistoryLoadFailed"),
            object: nil
        )
    }
    
    // MARK: - History Load Failure Handler
    
    @objc private func handleHistoryLoadFailedNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let roomJID = userInfo["roomJID"] as? String else {
            return
        }
        
        // Only handle failures for this room
        let normalizedFailedRoom = roomJID.components(separatedBy: "/").first ?? roomJID
        let normalizedCurrentRoom = room.jid.components(separatedBy: "/").first ?? room.jid
        
        guard normalizedFailedRoom == normalizedCurrentRoom else {
            return
        }
        
        //print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        //print("❌ ChatRoomViewModel: History load failed notification received")
        //print("   Room: \(roomJID)")
        if let errorType = userInfo["errorType"] as? String {
            //print("   Error Type: \(errorType)")
        }
        if let errorCondition = userInfo["errorCondition"] as? String {
            //print("   Error Condition: \(errorCondition)")
        }
        if let errorText = userInfo["errorText"] as? String, !errorText.isEmpty {
            //print("   Error Text: \(errorText)")
        }
        //print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        Task { @MainActor in
            isLoading = false
            isRefreshing = false
            
            // Set user-friendly error message
            if let errorCondition = userInfo["errorCondition"] as? String {
                switch errorCondition {
                case "not-allowed":
                    loadError = "You don't have permission to view this chat's history."
                case "item-not-found":
                    loadError = "Chat history not found."
                case "forbidden":
                    loadError = "Access to chat history is forbidden."
                case "feature-not-implemented":
                    loadError = "Message history is not available for this chat."
                default:
                    loadError = "Failed to load messages. Pull down to retry."
                }
            } else if let errorText = userInfo["errorText"] as? String, !errorText.isEmpty {
                loadError = errorText
            } else {
                loadError = "Failed to load messages. Pull down to retry."
            }
            
            // Schedule retry with exponential backoff
            scheduleHistoryRetry()
        }
    }
    
    // MARK: - Retry Logic
    
    private var historyRetryAttempts = 0
    private let maxHistoryRetryAttempts = 3
    
    private func scheduleHistoryRetry() {
        guard historyRetryAttempts < maxHistoryRetryAttempts else {
            //print("⚠️ Max retry attempts reached for history loading")
            return
        }
        
        historyRetryAttempts += 1
        let delay = Double(historyRetryAttempts) * 2.0 // 2s, 4s, 6s
        
        //print("⏳ Scheduling history retry attempt \(historyRetryAttempts)/\(maxHistoryRetryAttempts) in \(delay)s")
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            
            // Only retry if still no messages and client is connected
            if messages.isEmpty && client.isFullyConnected() {
                //print("🔄 Retrying history load (attempt \(historyRetryAttempts))")
                loadError = nil
                loadMessages(forceReload: true)
            }
        }
    }
    
    /// Reset retry counter (call this when history loads successfully)
    private func resetHistoryRetry() {
        historyRetryAttempts = 0
    }
    
    @objc private func handleIncomingMessageNotification(_ notification: Notification) {
        print("🔔 ChatRoomViewModel.handleIncomingMessageNotification: Notification received")
        print("   Notification name: \(notification.name.rawValue)")
        print("   Current room.jid: '\(room.jid)'")
        
        guard let userInfo = notification.userInfo,
              let message = userInfo["message"] as? Message else {
            print("❌ ChatRoomViewModel.handleIncomingMessageNotification: SKIPPED - Invalid notification data")
            if let userInfo = notification.userInfo {
                print("   userInfo keys: \(userInfo.keys)")
                print("   message type: \(type(of: userInfo["message"]))")
            } else {
                print("   userInfo is nil")
            }
            return
        }
        
        print("✅ ChatRoomViewModel.handleIncomingMessageNotification: Message extracted from notification")
        print("   Message ID: '\(message.id)'")
        print("   Message body: '\(message.body)'")
        print("   Message roomJid: '\(message.roomJid)'")
        
        // Only handle messages for this room
        let normalizedMessageRoom = message.roomJid.components(separatedBy: "/").first ?? message.roomJid
        let normalizedCurrentRoom = room.jid.components(separatedBy: "/").first ?? room.jid
        
        print("🔍 ChatRoomViewModel.handleIncomingMessageNotification: Checking room match")
        print("   normalizedMessageRoom: '\(normalizedMessageRoom)'")
        print("   normalizedCurrentRoom: '\(normalizedCurrentRoom)'")
        print("   Match: \(normalizedMessageRoom == normalizedCurrentRoom)")
        
        guard normalizedMessageRoom == normalizedCurrentRoom else {
            print("❌ ChatRoomViewModel.handleIncomingMessageNotification: SKIPPED - Message is for different room")
            print("   Message room: '\(normalizedMessageRoom)'")
            print("   Current room: '\(normalizedCurrentRoom)'")
            return
        }
        
        print("✅ ChatRoomViewModel.handleIncomingMessageNotification: Room matches - calling handleIncomingMessage")
        
        // Handle the incoming message
        handleIncomingMessage(message)
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
        
        //print("⌨️ ChatRoomViewModel: Composing changed - isTyping: \(isComposing), users: \(composingList)")
        
        // Filter out current user from composing list (don't show typing indicator for yourself)
        let filteredComposingList = composingList.filter { userId in
            // Normalize user IDs for comparison
            let normalizedUserId = userId.lowercased().trimmingCharacters(in: .whitespaces)
            let normalizedCurrentId = currentUserId.lowercased().trimmingCharacters(in: .whitespaces)
            
            // Also check XMPP username if available
            if let currentXmpp = currentUserXmppUsername {
                let normalizedCurrentXmpp = currentXmpp.lowercased().trimmingCharacters(in: .whitespaces)
                let normalizedUserXmpp = userId.lowercased().trimmingCharacters(in: .whitespaces)
                if normalizedUserXmpp == normalizedCurrentXmpp {
                    return false
                }
            }
            
            return normalizedUserId != normalizedCurrentId
        }
        
        // Update UI on main thread
        Task { @MainActor in
            self.isTyping = !filteredComposingList.isEmpty
            self.composingUsers = filteredComposingList
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
        
        //print("📚 ChatRoomViewModel: History complete updated - complete: \(historyComplete)")
        
        // Clear errors and reset retry counter when history is successfully loaded
        Task { @MainActor in
            if loadError != nil && !messages.isEmpty {
                loadError = nil
            }
            
            // Reset retry counter on successful load
            resetHistoryRetry()
            
            // Update room's historyComplete flag
            self.room.historyComplete = historyComplete
            if historyComplete {
                //print("✅ ChatRoomViewModel: History is complete for room \(room.jid) - scroll-to-load disabled")
            }
        }
    }
    
    @objc private func handleReactionNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let notificationRoomJID = userInfo["roomJID"] as? String,
              let messageId = userInfo["messageId"] as? String,
              let reactions = userInfo["reactions"] as? [String],
              let from = userInfo["from"] as? String,
              let data = userInfo["data"] as? [String: String] else {
            return
        }
        
        // Only handle for this room
        let normalizedNotificationRoom = notificationRoomJID.components(separatedBy: "/").first ?? notificationRoomJID
        let normalizedCurrentRoom = room.jid.components(separatedBy: "/").first ?? room.jid
        
        guard normalizedNotificationRoom == normalizedCurrentRoom else {
            return
        }
        
        //print("👍 ChatRoomViewModel: Reaction received for message \(messageId)")
        
        // Update local messages array
        Task { @MainActor in
            if let index = messages.firstIndex(where: { $0.id == messageId }) {
                var updatedMessage = messages[index]
                if updatedMessage.reaction == nil {
                    updatedMessage.reaction = [:]
                }
                let fromId = from.components(separatedBy: "@").first ?? from
                if reactions.isEmpty {
                    updatedMessage.reaction?.removeValue(forKey: fromId)
                } else {
                    updatedMessage.reaction?[fromId] = ReactionMessage(emoji: reactions, data: data)
                }
                messages[index] = updatedMessage
                room.messages = messages
                
                // CRITICAL: Save updated message to cache immediately
                MessageCache.shared.saveMessages(messages, forRoomJID: room.jid)
            }
        }
    }
    
    @objc private func handleDeleteNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let notificationRoomJID = userInfo["roomJID"] as? String,
              let messageId = userInfo["messageId"] as? String else {
            return
        }
        
        // Only handle for this room
        let normalizedNotificationRoom = notificationRoomJID.components(separatedBy: "/").first ?? notificationRoomJID
        let normalizedCurrentRoom = room.jid.components(separatedBy: "/").first ?? room.jid
        
        guard normalizedNotificationRoom == normalizedCurrentRoom else {
            return
        }
        
        print("🗑️ ChatRoomViewModel: Message deleted from XMPP for message \(messageId)")
        print("   Current messages count: \(messages.count)")
        
        // Match TypeScript EXACTLY: deleteRoomMessage filters out the message completely
        // From roomsSlice.ts lines 109-111:
        // state.rooms[roomJID].messages = state.rooms[roomJID].messages.filter(
        //   (message) => message.id !== messageId
        // );
        Task { @MainActor in
            let messagesBeforeDelete = messages.count
            messages = messages.filter { $0.id != messageId }
            room.messages = messages
            
            print("✅ ChatRoomViewModel.handleDeleteNotification: Message removed from array")
            print("   Messages before: \(messagesBeforeDelete), after: \(messages.count)")
            
            // CRITICAL: Save updated messages array to cache immediately
            MessageCache.shared.saveMessages(messages, forRoomJID: room.jid)
            print("💾 ChatRoomViewModel.handleDeleteNotification: Saved updated messages to cache")
        }
    }
    
    @objc private func handleEditNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let notificationRoomJID = userInfo["roomJID"] as? String,
              let messageId = userInfo["messageId"] as? String,
              let newText = userInfo["newText"] as? String else {
            print("❌ ChatRoomViewModel.handleEditNotification: Missing required userInfo")
            return
        }
        
        // Only handle for this room
        let normalizedNotificationRoom = notificationRoomJID.components(separatedBy: "/").first ?? notificationRoomJID
        let normalizedCurrentRoom = room.jid.components(separatedBy: "/").first ?? room.jid
        
        guard normalizedNotificationRoom == normalizedCurrentRoom else {
            print("⚠️ ChatRoomViewModel.handleEditNotification: Room mismatch. Notification room: \(normalizedNotificationRoom), current room: \(normalizedCurrentRoom)")
            return
        }
        
        print("✏️ ChatRoomViewModel: Message edited from XMPP for message \(messageId) with new text: '\(newText)'")
        print("   Current messages count: \(messages.count)")
        
        // Update local messages array - update body
        Task { @MainActor in
            if let index = messages.firstIndex(where: { $0.id == messageId }) {
                print("✅ ChatRoomViewModel.handleEditNotification: Found message at index \(index), updating")
                var updatedMessage = messages[index]
                let editedMessage = Message(
                    id: updatedMessage.id,
                    user: updatedMessage.user,
                    date: updatedMessage.date,
                    body: newText,
                    roomJid: updatedMessage.roomJid,
                    key: updatedMessage.key,
                    coinsInMessage: updatedMessage.coinsInMessage,
                    numberOfReplies: updatedMessage.numberOfReplies,
                    isSystemMessage: updatedMessage.isSystemMessage,
                    isMediafile: updatedMessage.isMediafile,
                    locationPreview: updatedMessage.locationPreview,
                    mimetype: updatedMessage.mimetype,
                    location: updatedMessage.location,
                    pending: updatedMessage.pending,
                    timestamp: updatedMessage.timestamp,
                    showInChannel: updatedMessage.showInChannel,
                    activeMessage: updatedMessage.activeMessage,
                    isReply: updatedMessage.isReply,
                    isDeleted: updatedMessage.isDeleted,
                    mainMessage: updatedMessage.mainMessage,
                    reply: updatedMessage.reply,
                    reaction: updatedMessage.reaction,
                    fileName: updatedMessage.fileName,
                    translations: updatedMessage.translations,
                    langSource: updatedMessage.langSource,
                    originalName: updatedMessage.originalName,
                    size: updatedMessage.size,
                    xmppId: updatedMessage.xmppId,
                    xmppFrom: updatedMessage.xmppFrom,
                    waveForm: updatedMessage.waveForm
                )
                messages[index] = editedMessage
                room.messages = messages
                
                print("✅ ChatRoomViewModel.handleEditNotification: Message updated. Total messages: \(messages.count)")
                print("   Message ID: \(editedMessage.id), Body: '\(editedMessage.body)'")
                
                // CRITICAL: Save updated message to cache immediately so it persists
                MessageCache.shared.saveMessages(messages, forRoomJID: room.jid)
                print("💾 ChatRoomViewModel.handleEditNotification: Saved edited message to cache")
            } else {
                print("❌ ChatRoomViewModel.handleEditNotification: Message with id \(messageId) not found in messages array!")
                print("   Available message IDs: \(messages.map { $0.id }.prefix(5))")
            }
        }
    }
    
    /// Set up XMPP client delegate to receive messages
    public func setupClientDelegate() {
        // Already set in setupObservers()
    }
    
    // MARK: - XMPPClientDelegate
    
    public func xmppClientDidConnect(_ client: XMPPClient) {
        //print("📡 ChatRoomViewModel: XMPP client connected")
    }
    
    public func xmppClientDidDisconnect(_ client: XMPPClient) {
        //print("📡 ChatRoomViewModel: XMPP client disconnected")
    }
    
    public func xmppClient(_ client: XMPPClient, didReceiveMessage message: Message) {
        // Handle the incoming message
        handleIncomingMessage(message)
    }
    
    public func xmppClient(_ client: XMPPClient, didReceiveStanza stanza: XMPPStanza) {
        // Stanza received - already handled by handleStanza
    }
    
    public func xmppClient(_ client: XMPPClient, didChangeStatus status: ConnectionStatus) {
        //print("📡 ChatRoomViewModel: Connection status changed: \(status.rawValue)")
    }
    
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
        
        //print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        //print("📜 loadMoreMessages CALLED")
        //print("   max: \(max)")
        //print("   beforeTimestamp param: \(beforeTimestamp?.description ?? "nil")")
        //print("   isLoadingMore: \(isLoadingMore)")
        //print("   historyComplete: \(room.historyComplete ?? false)")
        //print("   📊 CURRENT MESSAGE COUNT: \(actualMessageCountBeforeLoad)")
        //print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        // Логуємо перше і останнє повідомлення в масиві
        if let firstMessage = messages.first {
            //print("📋 FIRST MESSAGE IN ARRAY:")
            //print("   id: \(firstMessage.id)")
            //print("   timestamp: \(firstMessage.timestamp?.description ?? "nil")")
            //print("   date: \(firstMessage.date)")
            //print("   body: \(firstMessage.body.prefix(50))...")
        } else {
            //print("📋 FIRST MESSAGE: NONE (array is empty)")
        }
        
        if let lastMessage = messages.last {
            //print("📋 LAST MESSAGE IN ARRAY:")
            //print("   id: \(lastMessage.id)")
            //print("   timestamp: \(lastMessage.timestamp?.description ?? "nil")")
            //print("   date: \(lastMessage.date)")
            //print("   body: \(lastMessage.body.prefix(50))...")
        } else {
            //print("📋 LAST MESSAGE: NONE (array is empty)")
        }
        
        //print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
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
                //print("📜 Using provided beforeTimestamp: \(before)")
                return before
            }
            
            // Find the oldest message (skip delimiter-new if present) - matches web version
            let firstMessage = messages.first(where: { $0.id != "delimiter-new" }) ?? messages.first
            
            guard let message = firstMessage else {
                //print("❌ No first message found to use as before parameter")
                return nil
            }
            
            // Match TypeScript: Number(firstMessageId) - try to convert message.id to number
            if let idAsNumber = Int64(message.id) {
                //print("📜 Converted message.id to number: \(message.id) -> \(idAsNumber)")
                return idAsNumber
            }
            
            // If message.id is not numeric (e.g., UUID), try timestamp
            if let timestamp = message.timestamp {
                //print("📜 Using message.timestamp: \(timestamp)")
                return timestamp
            }
            
            // Last resort: convert date to timestamp (milliseconds)
            let dateTimestamp = Int64(message.date.timeIntervalSince1970 * 1000)
            //print("📜 Using date conversion: \(dateTimestamp)")
            return dateTimestamp
        }()
        
        guard let before = beforeMessageId else {
            print("❌ ChatRoomViewModel.loadMoreMessages: Could not determine 'before' parameter, aborting history request")
            return
        }
        
        //print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        //print("🎯 FINAL BEFORE PARAMETER TO SEND:")
        //print("   Value: \(before)")
        if let firstMsg = messages.first(where: { $0.id != "delimiter-new" }) ?? messages.first {
            //print("   Source message:")
            //print("      id: '\(firstMsg.id)'")
            //print("      id as Int64: \(Int64(firstMsg.id)?.description ?? "FAILED - not numeric")")
            //print("      timestamp: \(firstMsg.timestamp?.description ?? "nil")")
            //print("      date: \(firstMsg.date)")
        }
        //print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
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
            //print("📌 Saved scroll position: messageId=\(firstMessage.id), count=\(messages.count)")
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
        //print("🔄 Pull to refresh triggered")
        
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
            //print("⚠️ Cannot refresh: client is offline")
            return
        }
        
        // Actually reload messages - this will send get-history query
        // Use forceReload to ensure we get fresh messages even if cached
        loadMessages(max: pageSize, before: nil, forceReload: true)
        
        //print("📥 Refresh: loadMessages called with forceReload=true")
        
        // Автоматично скидаємо прапорець через 5 секунд, якщо повідомлення не прийшли
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 секунд
            if isRefreshing {
                isRefreshing = false
                // Set error if still refreshing after timeout and no new messages
                let messageCountAfterRefresh = messages.count
                if messageCountAfterRefresh == messageCountBeforeRefresh || messages.isEmpty {
                    loadError = "Failed to load new messages. Pull down to retry."
                    //print("❌ Refresh failed: no new messages received")
                }
                //print("⏱️ Refresh timeout - скидаємо прапорець")
            }
        }
    }
    
    /// Load message history from XMPP
    /// Sends get-history MAM query - messages will be received through onMessageHistory handler in StanzaHandlers
    public func loadMessages(max: Int = 30, before: Int64? = nil, forceReload: Bool = false) {
        // If messages are already loaded and we're not forcing a reload, just ensure they're displayed
        if messagesLoaded && !forceReload && !messages.isEmpty {
            //print("📋 ChatRoomViewModel: Messages already loaded (\(messages.count) messages), skipping reload")
            // Trigger a refresh to ensure UI updates
            objectWillChange.send()
            return
        }
        
        //print("📋 ChatRoomViewModel: loadMessages called")
        //print("   Room: \(room.jid), max: \(max), before: \(before?.description ?? "nil")")
        //print("   Client status: \(client.status.rawValue), presencesReady: \(client.presencesReady)")
        
        // Clear any previous errors
        loadError = nil
        
        // Check if client is fully connected (online AND presences ready)
        // This prevents sending queries before the XMPP connection is fully established
        guard client.isFullyConnected() else {
            let isOnline = client.checkOnline()
            let presencesReady = client.presencesReady
            
            if !isOnline {
                //print("⚠️ Client is not online. Status: \(client.status.rawValue)")
            } else if !presencesReady {
                //print("⚠️ Client is online but presences not ready yet")
            }
            
            // Show cached messages while waiting
            if let cachedMessages = MessageCache.shared.loadMessages(forRoomJID: room.jid) {
                messages = cachedMessages
                room.messages = cachedMessages
                messagesLoaded = true
                //print("📂 ChatRoomViewModel: Showing \(cachedMessages.count) cached messages while waiting for connection")
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
                        //print("✅ Client is now fully connected (attempt \(attempts)), sending get-history query...")
                        loadError = nil
                        loadMessages(max: max, before: before, forceReload: forceReload)
                        return
                    }
                    
                    //print("⏳ Waiting for full connection... attempt \(attempts)/\(maxAttempts)")
                }
                
                //print("❌ Client did not become fully connected within timeout")
                loadError = "Connection timeout. Pull down to retry."
            }
            return
        }
        
        // Check if we have cached messages - if so, show them immediately and load in background
        if let cachedMessages = MessageCache.shared.loadMessages(forRoomJID: room.jid), !forceReload {
            messages = cachedMessages
            room.messages = cachedMessages
            messagesLoaded = true
            //print("📂 ChatRoomViewModel: Using \(cachedMessages.count) cached messages, loading fresh in background")
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
        
        //print("✅ Get-history query sent. Expecting \(max) messages.")
        
        // Set a timeout to hide loader if messages don't arrive within 10 seconds
        Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            if isLoading {
                //print("⏱️ Loading timeout reached. Hiding loader.")
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
    private func loadCachedMessages() {
        if let cachedMessages = MessageCache.shared.loadMessages(forRoomJID: room.jid) {
            messages = cachedMessages
            room.messages = cachedMessages
            messagesLoaded = true
            //print("📂 ChatRoomViewModel: Loaded \(cachedMessages.count) cached messages for room: \(room.jid)")
        }
    }
    
    /// Called when view appears - ensures messages are displayed
    public func onViewAppeared() {
        // Guard: Don't load if already loading to prevent multiple simultaneous requests
        guard !isLoading && !isLoadingMore else {
            //print("📋 ChatRoomViewModel: Already loading, skipping onViewAppeared load")
            return
        }
        
        // If messages are already loaded, just ensure they're displayed
        if messagesLoaded && !messages.isEmpty {
            //print("📋 ChatRoomViewModel: View appeared, displaying \(messages.count) existing messages")
            // Trigger a refresh to ensure UI updates
            objectWillChange.send()
        } else {
            // Wait a bit to ensure XMPP connection is stable before loading
            Task { @MainActor in
                // Small delay to ensure connection is stable
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                
                // Check connection again before loading
                guard client.checkOnline() else {
                    //print("⚠️ ChatRoomViewModel: Client not online, will retry when connection is established")
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
        
        //print("🔥🔥🔥 CHATROOMVIEWMODEL.SENDMESSAGE CALLED 🔥🔥🔥")
        //print("📤 Sending message: \(text)")
        
        // Get current user info from UserStore
        let user = UserStore.shared.currentUser
        let firstName = user?.firstName ?? "User"
        let lastName = user?.lastName ?? "Name"
        let walletAddress = user?.walletAddress ?? ""
        let photo = user?.profileImage ?? ""
        
        //print("👤 User info: \(firstName) \(lastName)")
        
        // Generate the same ID that will be sent to server
        // This matches the logic in SendTextMessage.swift: "send-text-message-\(timestamp)"
        let messageId = "send-text-message-\(Int64(Date().timeIntervalSince1970 * 1000))"
        
        client.operations.sendTextMessage(
            roomJID: room.jid,
            firstName: firstName,
            lastName: lastName,
            photo: photo,
            walletAddress: walletAddress,
            userMessage: text,
            customId: messageId
        )
        
        // Add message optimistically to UI (will be confirmed when received from server)
        // Use the SAME ID that was sent to server, so server can match it via xmppId
        let optimisticMessage = Message(
            id: messageId,
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
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            xmppId: messageId // Store the sent ID so we can match it when server confirms
        )
        
        messages.append(optimisticMessage)
        
        // Update room's messages array
        room.messages = messages
        
        // CRITICAL: Save pending message to cache immediately so it persists even if connection is lost
        // This ensures the message will still be visible after app restart
        MessageCache.shared.saveMessages(messages, forRoomJID: room.jid)
    }
    
    /// Send reply to a message
    public func sendReply(messageId: String, text: String, alsoSendToMain: Bool) {
        guard !text.isEmpty else { return }
        
        //print("💬 ChatRoomViewModel: Sending reply to message \(messageId)")
        
        // Get current user info from UserStore
        let user = UserStore.shared.currentUser
        let firstName = user?.firstName ?? "User"
        let lastName = user?.lastName ?? "Name"
        let walletAddress = user?.walletAddress ?? ""
        let photo = user?.profileImage ?? ""
        
        // Send reply message with mainMessage set
        client.operations.sendTextMessage(
            roomJID: room.jid,
            firstName: firstName,
            lastName: lastName,
            photo: photo,
            walletAddress: walletAddress,
            userMessage: text,
            isReply: true,
            mainMessage: messageId
        )
        
        // If alsoSendToMain is true, send another message without mainMessage
        if alsoSendToMain {
            client.operations.sendTextMessage(
                roomJID: room.jid,
                firstName: firstName,
                lastName: lastName,
                photo: photo,
                walletAddress: walletAddress,
                userMessage: text,
                isReply: false,
                mainMessage: nil
            )
        }
        
        // Add optimistic reply message to UI
        let optimisticReply = Message(
            id: "pending-reply-\(Int64(Date().timeIntervalSince1970 * 1000))",
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
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            isReply: true,
            mainMessage: messageId
        )
        
        messages.append(optimisticReply)
        
        // Update room's messages array
        room.messages = messages
        
        // CRITICAL: Save pending message to cache immediately so it persists even if connection is lost
        MessageCache.shared.saveMessages(messages, forRoomJID: room.jid)
    }
    
    /// Handle incoming real-time message
    /// Matches TypeScript: store.dispatch(addRoomMessage({ roomJID, message }))
    public func handleIncomingMessage(_ message: Message) {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔵 ChatRoomViewModel.handleIncomingMessage: START")
        print("   Message ID: '\(message.id)'")
        print("   Message body: '\(message.body)'")
        print("   Message body.isEmpty: \(message.body.isEmpty)")
        print("   Message body.count: \(message.body.count)")
        print("   Message xmppId: '\(message.xmppId ?? "nil")'")
        print("   Message timestamp: \(message.timestamp?.description ?? "nil")")
        print("   Message roomJid: '\(message.roomJid)'")
        print("   Message user.id: '\(message.user.id)'")
        print("   Message pending: \(message.pending)")
        print("   Current room.jid: '\(room.jid)'")
        print("   Current messages.count: \(messages.count)")
        print("   isLoadingMore: \(isLoadingMore)")
        print("   isLoading: \(isLoading)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        // Clear any errors when we successfully receive a message
        if loadError != nil {
            loadError = nil
        }
        
        // Match TypeScript: Only add if message has body
        // if (!message?.body) return;
        // CRITICAL: Allow empty body for media messages or system messages
        let hasBody = !message.body.isEmpty
        let isMediaMessage = message.isMediafile == "true" || message.mimetype != nil
        let isSystemMessage = message.isSystemMessage == "true" || message.isSystemMessage == "1"
        
        print("🔍 ChatRoomViewModel.handleIncomingMessage: Body check")
        print("   hasBody: \(hasBody)")
        print("   isMediaMessage: \(isMediaMessage)")
        print("   isSystemMessage: \(isSystemMessage)")
        print("   body.isEmpty: \(message.body.isEmpty)")
        print("   body: '\(message.body)'")
        
        guard hasBody || isMediaMessage || isSystemMessage else {
            print("❌ ChatRoomViewModel.handleIncomingMessage: SKIPPED - message body is empty and not media/system")
            print("   Message ID: '\(message.id)'")
            print("   Message has media: \(message.isMediafile == "true")")
            print("   Message mimetype: '\(message.mimetype ?? "nil")'")
            print("   Message isSystemMessage: \(message.isSystemMessage)")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            return
        }
        
        if !hasBody && (isMediaMessage || isSystemMessage) {
            print("✅ ChatRoomViewModel.handleIncomingMessage: Allowing message with empty body (media/system message)")
        }
        
        print("✅ ChatRoomViewModel.handleIncomingMessage: Message body check passed")
        
        // Match TypeScript: Check if room exists
        // const roomExist = !!state?.rooms[roomJID];
        // if (!roomExist) { return; }
        // For Swift, we check if the message is for this room
        // Extract bare JID (without resource) for comparison
        // The roomJID passed from StanzaHandlers is already the bare JID
        let messageRoomBareJID = message.roomJid.components(separatedBy: "/").first ?? message.roomJid
        let currentRoomBareJID = room.jid.components(separatedBy: "/").first ?? room.jid
        
        print("🔍 ChatRoomViewModel.handleIncomingMessage: Checking room match")
        print("   messageRoomBareJID: '\(messageRoomBareJID)'")
        print("   currentRoomBareJID: '\(currentRoomBareJID)'")
        print("   Match: \(messageRoomBareJID == currentRoomBareJID)")
        
        guard messageRoomBareJID == currentRoomBareJID else {
            // Message is for a different room, ignore it
            print("❌ ChatRoomViewModel.handleIncomingMessage: SKIPPED - Message is for different room")
            print("   Message room: '\(messageRoomBareJID)'")
            print("   Current room: '\(currentRoomBareJID)'")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            return
        }
        
        print("✅ ChatRoomViewModel.handleIncomingMessage: Room matches, processing message")
        print("📥 ChatRoomViewModel.handleIncomingMessage: Received message with id: '\(message.id)', body: '\(message.body.prefix(50))', xmppId: '\(message.xmppId ?? "nil")'")
        print("   Current messages count: \(messages.count)")
        print("   isLoadingMore: \(isLoadingMore)")
        
        // Check if message already exists in array
        print("🔍 ChatRoomViewModel.handleIncomingMessage: Checking for existing message with matching ID")
        let existingMessageIndices = messages.enumerated().compactMap { index, msg -> (Int, String)? in
            let matches = msg.id == message.id ||
                (message.xmppId != nil && msg.id == message.xmppId) ||
                (msg.xmppId != nil && msg.xmppId == message.id) ||
                (msg.xmppId != nil && message.xmppId != nil && msg.xmppId == message.xmppId)
            if matches {
                return (index, msg.id)
            }
            return nil
        }
        
        if !existingMessageIndices.isEmpty {
            print("🔍 ChatRoomViewModel.handleIncomingMessage: Found \(existingMessageIndices.count) existing message(s) with matching ID:")
            for (index, msgId) in existingMessageIndices {
                let existingMsg = messages[index]
                print("   Index \(index): ID='\(msgId)', body='\(existingMsg.body.prefix(30))', pending=\(existingMsg.pending)")
            }
        } else {
            print("✅ ChatRoomViewModel.handleIncomingMessage: No existing message found with matching ID - will add as new")
        }
        
        // CRITICAL FIX: When loading older history (isLoadingMore == true), we should NOT update existing messages
        // unless they are pending messages that need confirmation. Older history messages should be added as new messages.
        // Only update if:
        // 1. We're NOT loading older history (isLoadingMore == false), OR
        // 2. The existing message is pending (needs confirmation)
        
        // Match: pending message id === incoming message xmppId
        // CRITICAL: Also check for edited messages - same ID but different body
        if let existingIndex = messages.firstIndex(where: { msg in
            // Exact ID match (this handles both regular messages and edited messages)
            msg.id == message.id ||
            // CRITICAL: If incoming message has xmppId, check if it matches existing message ID
            // This handles the case: pending message id = "send-text-message-123", 
            // incoming message xmppId = "send-text-message-123"
            (message.xmppId != nil && msg.id == message.xmppId) ||
            // If existing message has xmppId, check if it matches incoming message ID
            (msg.xmppId != nil && msg.xmppId == message.id) ||
            // Also check: if both have xmppId and they match
            (msg.xmppId != nil && message.xmppId != nil && msg.xmppId == message.xmppId)
        }) {
            print("🔍 ChatRoomViewModel.handleIncomingMessage: Found existing message at index \(existingIndex)")
            let existingMessage = messages[existingIndex]
            
            // CRITICAL: When loading older history, only update if it's a pending message that needs confirmation
            // Otherwise, skip the update because it's a duplicate message that already exists
            if isLoadingMore {
                // Check if this is a pending message that needs confirmation
                let isPendingMessage = existingMessage.pending == true
                
                if !isPendingMessage {
                    // Message already exists and is not pending - skip duplicate during history load
                    // This happens when loading older history and the message is already in the array (from cache or previous load)
                    print("⚠️ ChatRoomViewModel.handleIncomingMessage: Message already exists during history load (not pending), skipping duplicate")
                    print("   Message ID: '\(message.id)', timestamp: \(message.timestamp?.description ?? "nil")")
                    print("   Existing message at index \(existingIndex): body='\(existingMessage.body.prefix(30))', pending=\(existingMessage.pending)")
                    print("   Incoming message: body='\(message.body.prefix(30))', pending=\(message.pending)")
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    
                    // Track that we received a message (even if duplicate) for history load completion
                    if isLoadingMore {
                        historyLoadReceivedCount += 1
                        let timeSinceStart = historyLoadStartTime.map { Date().timeIntervalSince($0) } ?? 0
                        
                        // Check if this duplicate message is actually OLDER than our oldest message
                        // If it is, it means we're receiving messages we already have, but there might be even older ones
                        let oldestMessageTimestamp = messages.first(where: { $0.id != "delimiter-new" })?.timestamp ?? Int64.max
                        let incomingTimestamp = message.timestamp ?? 0
                        let isOlderThanOldest = incomingTimestamp < oldestMessageTimestamp
                        
                        if isOlderThanOldest {
                            print("📜 ChatRoomViewModel.handleIncomingMessage: Duplicate message is older than oldest (\(incomingTimestamp) < \(oldestMessageTimestamp)) - may need to request even older messages")
                        }
                        
                        // Reset isLoadingMore if we've received enough messages or waited long enough
                        // This handles the case where all messages are duplicates
                        if historyLoadReceivedCount >= pageSize || timeSinceStart >= 2.0 {
                            isLoadingMore = false
                            scrollPositionBeforeLoad = nil
                            let receivedCount = historyLoadReceivedCount
                            historyLoadReceivedCount = 0
                            historyLoadStartTime = nil
                            print("✅ ChatRoomViewModel.handleIncomingMessage: Reset isLoadingMore after receiving \(receivedCount) messages (including duplicates) during history load")
                            
                            // If all messages were duplicates and we received the expected amount,
                            // it might mean we've loaded all available history up to this point
                            // The UI can trigger another load if needed with an even older before parameter
                        } else {
                            // Debounced reset - wait for more messages or timeout
                            loadingMoreTask?.cancel()
                            loadingMoreTask = Task {
                                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second silence = batch done
                                if isLoadingMore {
                                    isLoadingMore = false
                                    scrollPositionBeforeLoad = nil
                                    let receivedCount = historyLoadReceivedCount
                                    historyLoadReceivedCount = 0
                                    historyLoadStartTime = nil
                                    print("✅ ChatRoomViewModel.handleIncomingMessage: Reset isLoadingMore after 1s silence during history load (received \(receivedCount) messages)")
                                }
                            }
                        }
                    }
                    
                    return
                } else {
                    // This is a pending message confirmation - update it
                    print("✅ ChatRoomViewModel.handleIncomingMessage: Updating pending message confirmation during history load")
                    // Continue with update logic below
                }
            }
            
            // Match TypeScript EXACTLY: Update existing message and set pending to false
            // From roomsSlice.ts lines 198-201:
            // roomMessages[existingIndex] = deepMerge(
            //   { ...roomMessages[existingIndex] },
            //   { ...message, pending: false }
            // );
            
            // Deep merge: keep existing values, but update with new message and set pending: false
            let updatedMessage = Message(
                id: message.id, // Use confirmed ID from server
                user: message.user,
                date: message.date,
                body: message.body,
                roomJid: message.roomJid,
                key: message.key ?? existingMessage.key,
                coinsInMessage: message.coinsInMessage ?? existingMessage.coinsInMessage,
                numberOfReplies: message.numberOfReplies ?? existingMessage.numberOfReplies,
                isSystemMessage: message.isSystemMessage ?? existingMessage.isSystemMessage,
                isMediafile: message.isMediafile ?? existingMessage.isMediafile,
                locationPreview: message.locationPreview ?? existingMessage.locationPreview,
                mimetype: message.mimetype ?? existingMessage.mimetype,
                location: message.location ?? existingMessage.location,
                pending: false, // Always set pending to false when confirmed
                timestamp: message.timestamp ?? existingMessage.timestamp,
                showInChannel: message.showInChannel ?? existingMessage.showInChannel,
                activeMessage: message.activeMessage ?? existingMessage.activeMessage,
                isReply: message.isReply ?? existingMessage.isReply,
                isDeleted: message.isDeleted ?? existingMessage.isDeleted,
                mainMessage: message.mainMessage ?? existingMessage.mainMessage,
                reply: message.reply ?? existingMessage.reply,
                reaction: message.reaction ?? existingMessage.reaction,
                fileName: message.fileName ?? existingMessage.fileName,
                translations: message.translations ?? existingMessage.translations,
                langSource: message.langSource ?? existingMessage.langSource,
                originalName: message.originalName ?? existingMessage.originalName,
                size: message.size ?? existingMessage.size,
                xmppId: message.xmppId ?? existingMessage.xmppId, // Keep xmppId if available
                xmppFrom: message.xmppFrom ?? existingMessage.xmppFrom,
                waveForm: message.waveForm ?? existingMessage.waveForm
            )
            
            // REPLACE existing message, don't add new one
            let oldBody = existingMessage.body
            messages[existingIndex] = updatedMessage
            room.messages = messages
            
            print("🔄 ChatRoomViewModel.handleIncomingMessage: Updated existing message at index \(existingIndex)")
            print("   Old body: '\(oldBody.prefix(50))'")
            print("   New body: '\(updatedMessage.body.prefix(50))'")
            print("   Total messages after update: \(messages.count)")
            
            // CRITICAL: Save updated message to cache immediately
            MessageCache.shared.saveMessages(messages, forRoomJID: room.jid)
            print("💾 ChatRoomViewModel.handleIncomingMessage: Saved updated message to cache")
            
            return
        }
        
        print("✅ ChatRoomViewModel.handleIncomingMessage: No exact ID match found - checking for edit or pending messages")
        
        // CRITICAL: Check if this might be an edited message - look for existing message with same ID but different body
        // This handles the case where server sends edited message as a new message with same ID
        let editedMessages = messages.enumerated().compactMap { index, msg -> (Int, String)? in
            if msg.id == message.id && msg.body != message.body {
                return (index, msg.body)
            }
            return nil
        }
        
        if !editedMessages.isEmpty {
            print("🔄 ChatRoomViewModel.handleIncomingMessage: Found \(editedMessages.count) existing message(s) with same ID but different body - likely edit confirmation")
            for (index, existingBody) in editedMessages {
                print("   Index \(index): Existing body='\(existingBody.prefix(50))', New body='\(message.body.prefix(50))'")
            }
        }
        
        if let editedIndex = messages.firstIndex(where: { msg in
            msg.id == message.id && msg.body != message.body
        }) {
            print("🔄 ChatRoomViewModel.handleIncomingMessage: Processing edit confirmation at index \(editedIndex)")
            print("   Existing body: '\(messages[editedIndex].body.prefix(50))'")
            print("   New body: '\(message.body.prefix(50))'")
            
            // Update the existing message with new body (edit confirmation)
            let existingMessage = messages[editedIndex]
            let updatedMessage = Message(
                id: message.id,
                user: message.user,
                date: message.date,
                body: message.body, // Use new body from server
                roomJid: message.roomJid,
                key: message.key ?? existingMessage.key,
                coinsInMessage: message.coinsInMessage ?? existingMessage.coinsInMessage,
                numberOfReplies: message.numberOfReplies ?? existingMessage.numberOfReplies,
                isSystemMessage: message.isSystemMessage ?? existingMessage.isSystemMessage,
                isMediafile: message.isMediafile ?? existingMessage.isMediafile,
                locationPreview: message.locationPreview ?? existingMessage.locationPreview,
                mimetype: message.mimetype ?? existingMessage.mimetype,
                location: message.location ?? existingMessage.location,
                pending: false, // Always set pending to false when confirmed
                timestamp: message.timestamp ?? existingMessage.timestamp,
                showInChannel: message.showInChannel ?? existingMessage.showInChannel,
                activeMessage: message.activeMessage ?? existingMessage.activeMessage,
                isReply: message.isReply ?? existingMessage.isReply,
                isDeleted: message.isDeleted ?? existingMessage.isDeleted,
                mainMessage: message.mainMessage ?? existingMessage.mainMessage,
                reply: message.reply ?? existingMessage.reply,
                reaction: message.reaction ?? existingMessage.reaction,
                fileName: message.fileName ?? existingMessage.fileName,
                translations: message.translations ?? existingMessage.translations,
                langSource: message.langSource ?? existingMessage.langSource,
                originalName: message.originalName ?? existingMessage.originalName,
                size: message.size ?? existingMessage.size,
                xmppId: message.xmppId ?? existingMessage.xmppId,
                xmppFrom: message.xmppFrom ?? existingMessage.xmppFrom,
                waveForm: message.waveForm ?? existingMessage.waveForm
            )
            
            messages[editedIndex] = updatedMessage
            room.messages = messages
            
            print("✅ ChatRoomViewModel.handleIncomingMessage: Updated message as edit confirmation")
            print("   Total messages after edit update: \(messages.count)")
            
            // CRITICAL: Save updated message to cache immediately
            MessageCache.shared.saveMessages(messages, forRoomJID: room.jid)
            print("💾 ChatRoomViewModel.handleIncomingMessage: Saved edited message to cache")
            
            return
        }
        
        print("🔍 ChatRoomViewModel.handleIncomingMessage: Checking if message is from current user")
        print("   message.user.id: '\(message.user.id)'")
        print("   message.user.xmppUsername: '\(message.user.xmppUsername ?? "nil")'")
        print("   message.xmppFrom: '\(message.xmppFrom ?? "nil")'")
        print("   currentUserId: '\(currentUserId)'")
        
        // CRITICAL FALLBACK: If message is from current user, aggressively find and replace ANY pending message
        // with same content, regardless of ID matching. This handles cases where server doesn't return our ID correctly.
        let isFromCurrentUser = message.user.id == currentUserId || 
                                message.user.xmppUsername == currentUserId ||
                                (message.xmppFrom != nil && (message.xmppFrom?.contains(currentUserId) == true || 
                                                              message.xmppFrom?.contains(message.user.xmppUsername ?? "") == true))
        
        print("   isFromCurrentUser: \(isFromCurrentUser)")
        
        if isFromCurrentUser {
            print("🔍 ChatRoomViewModel.handleIncomingMessage: Message is from current user - checking for pending messages with same body")
            print("   Looking for pending messages with body: '\(message.body.prefix(30))'")
            // Find ALL pending messages with same content from current user
            let pendingIndices = messages.enumerated().compactMap { index, msg -> Int? in
                guard msg.pending == true else { return nil }
                guard msg.body == message.body else { return nil }
                
                // Check if it's from current user
                let msgIsFromCurrentUser = msg.user.id == currentUserId || 
                                          msg.user.xmppUsername == currentUserId ||
                                          msg.user.id == message.user.id ||
                                          msg.user.xmppUsername == message.user.xmppUsername
                
                if msgIsFromCurrentUser {
                    print("   Found pending message at index \(index): ID='\(msg.id)', body='\(msg.body.prefix(30))'")
                }
                
                return msgIsFromCurrentUser ? index : nil
            }
            
            print("   Found \(pendingIndices.count) pending message(s) with matching body from current user")
            
            // Replace the FIRST pending message found (or remove all if multiple)
            if let pendingIndex = pendingIndices.first {
                print("✅ ChatRoomViewModel.handleIncomingMessage: Replacing pending message at index \(pendingIndex)")
                // Replace pending message with confirmed one
                let pendingMessage = messages[pendingIndex]
            let updatedMessage = Message(
                id: message.id, // Use confirmed ID from server
                user: message.user,
                date: message.date,
                body: message.body,
                roomJid: message.roomJid,
                key: message.key ?? pendingMessage.key,
                coinsInMessage: message.coinsInMessage ?? pendingMessage.coinsInMessage,
                numberOfReplies: message.numberOfReplies ?? pendingMessage.numberOfReplies,
                isSystemMessage: message.isSystemMessage ?? pendingMessage.isSystemMessage,
                isMediafile: message.isMediafile ?? pendingMessage.isMediafile,
                locationPreview: message.locationPreview ?? pendingMessage.locationPreview,
                mimetype: message.mimetype ?? pendingMessage.mimetype,
                location: message.location ?? pendingMessage.location,
                pending: false, // Set pending to false
                timestamp: message.timestamp ?? pendingMessage.timestamp,
                showInChannel: message.showInChannel ?? pendingMessage.showInChannel,
                activeMessage: message.activeMessage ?? pendingMessage.activeMessage,
                isReply: message.isReply ?? pendingMessage.isReply,
                isDeleted: message.isDeleted ?? pendingMessage.isDeleted,
                mainMessage: message.mainMessage ?? pendingMessage.mainMessage,
                reply: message.reply ?? pendingMessage.reply,
                reaction: message.reaction ?? pendingMessage.reaction,
                fileName: message.fileName ?? pendingMessage.fileName,
                translations: message.translations ?? pendingMessage.translations,
                langSource: message.langSource ?? pendingMessage.langSource,
                originalName: message.originalName ?? pendingMessage.originalName,
                size: message.size ?? pendingMessage.size,
                xmppId: message.xmppId ?? pendingMessage.xmppId,
                xmppFrom: message.xmppFrom ?? pendingMessage.xmppFrom,
                waveForm: message.waveForm ?? pendingMessage.waveForm
            )
                messages[pendingIndex] = updatedMessage
                
                // Remove any other pending messages with same content (duplicates)
                if pendingIndices.count > 1 {
                    print("⚠️ ChatRoomViewModel.handleIncomingMessage: Found \(pendingIndices.count) duplicate pending messages, removing extras")
                    for index in pendingIndices.dropFirst().reversed() {
                        messages.remove(at: index)
                    }
                }
                
                room.messages = messages
                
                print("✅ ChatRoomViewModel.handleIncomingMessage: Replaced pending message at index \(pendingIndex)")
                print("   Total messages after replacement: \(messages.count)")
                
                // CRITICAL: Save updated message to cache immediately
                MessageCache.shared.saveMessages(messages, forRoomJID: room.jid)
                print("💾 ChatRoomViewModel.handleIncomingMessage: Saved replaced message to cache")
                
                return
            }
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
        
        print("🔍 ChatRoomViewModel.handleIncomingMessage: Final duplicate check before adding")
        print("   isLoadingMore: \(isLoadingMore)")
        
        // FINAL CHECK: Before adding, make sure we don't already have this message
        // (in case it was added/updated in one of the checks above)
        // CRITICAL: Also check for messages with same ID but different body (edited messages)
        // CRITICAL FIX: When loading older history, skip this duplicate check - we already handled it above
        // and older messages should be allowed through even if they exist (they'll be deduplicated by sorting)
        let duplicateCheckMessages = messages.filter { msg in
            msg.id == message.id ||
            (message.xmppId != nil && msg.id == message.xmppId) ||
            (msg.xmppId != nil && msg.xmppId == message.id) ||
            (msg.xmppId != nil && message.xmppId != nil && msg.xmppId == message.xmppId)
        }
        
        print("   Found \(duplicateCheckMessages.count) potential duplicate(s) in final check")
        for (index, dupMsg) in messages.enumerated() where duplicateCheckMessages.contains(where: { $0.id == dupMsg.id }) {
            print("     Index \(index): ID='\(dupMsg.id)', body='\(dupMsg.body.prefix(30))', pending=\(dupMsg.pending)")
        }
        
        let alreadyExists = !isLoadingMore && !duplicateCheckMessages.isEmpty
        
        if alreadyExists {
            // Message already exists, don't add duplicate
            // But if body is different, it might be an edit - this should have been handled above
            print("⚠️ ChatRoomViewModel.handleIncomingMessage: Message already exists in final check, skipping duplicate")
            print("   Message ID: '\(message.id)'")
            print("   Found \(duplicateCheckMessages.count) duplicate(s), checking if it's an edit...")
            
            // Double-check: if body is different, update it (edit confirmation)
            if let existingIndex = messages.firstIndex(where: { $0.id == message.id && $0.body != message.body }) {
                print("🔄 ChatRoomViewModel.handleIncomingMessage: Found existing message with same ID but different body - updating as edit")
                let existingMessage = messages[existingIndex]
                let updatedMessage = Message(
                    id: message.id,
                    user: message.user,
                    date: message.date,
                    body: message.body,
                    roomJid: message.roomJid,
                    key: message.key ?? existingMessage.key,
                    coinsInMessage: message.coinsInMessage ?? existingMessage.coinsInMessage,
                    numberOfReplies: message.numberOfReplies ?? existingMessage.numberOfReplies,
                    isSystemMessage: message.isSystemMessage ?? existingMessage.isSystemMessage,
                    isMediafile: message.isMediafile ?? existingMessage.isMediafile,
                    locationPreview: message.locationPreview ?? existingMessage.locationPreview,
                    mimetype: message.mimetype ?? existingMessage.mimetype,
                    location: message.location ?? existingMessage.location,
                    pending: false,
                    timestamp: message.timestamp ?? existingMessage.timestamp,
                    showInChannel: message.showInChannel ?? existingMessage.showInChannel,
                    activeMessage: message.activeMessage ?? existingMessage.activeMessage,
                    isReply: message.isReply ?? existingMessage.isReply,
                    isDeleted: message.isDeleted ?? existingMessage.isDeleted,
                    mainMessage: message.mainMessage ?? existingMessage.mainMessage,
                    reply: message.reply ?? existingMessage.reply,
                    reaction: message.reaction ?? existingMessage.reaction,
                    fileName: message.fileName ?? existingMessage.fileName,
                    translations: message.translations ?? existingMessage.translations,
                    langSource: message.langSource ?? existingMessage.langSource,
                    originalName: message.originalName ?? existingMessage.originalName,
                    size: message.size ?? existingMessage.size,
                    xmppId: message.xmppId ?? existingMessage.xmppId,
                    xmppFrom: message.xmppFrom ?? existingMessage.xmppFrom,
                    waveForm: message.waveForm ?? existingMessage.waveForm
                )
                messages[existingIndex] = updatedMessage
                room.messages = messages
                MessageCache.shared.saveMessages(messages, forRoomJID: room.jid)
                print("✅ ChatRoomViewModel.handleIncomingMessage: Updated existing message as edit confirmation")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("🟢 ChatRoomViewModel.handleIncomingMessage: COMPLETE (edit update)")
                print("   Final message count: \(messages.count)")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                return
            }
            print("❌ ChatRoomViewModel.handleIncomingMessage: SKIPPED - Message already exists and not an edit")
            print("   Message ID: '\(message.id)'")
            print("   Message body: '\(message.body.prefix(50))'")
            print("   isLoadingMore: \(isLoadingMore)")
            print("   Duplicate check found \(duplicateCheckMessages.count) matching message(s)")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            return
        }
        
        print("✅ ChatRoomViewModel.handleIncomingMessage: Passed final duplicate check - proceeding to add message")
        
        // Add the actual message
        let messageCountBeforeAdd = messages.count
        print("➕ ChatRoomViewModel.handleIncomingMessage: ADDING NEW MESSAGE")
        print("   Message count before add: \(messageCountBeforeAdd)")
        print("   Message ID: '\(message.id)'")
        print("   Message body: '\(message.body.prefix(50))'")
        print("   Message timestamp: \(message.timestamp?.description ?? "nil")")
        print("   Message pending: \(message.pending)")
        
        messages.append(message)
        print("✅ ChatRoomViewModel.handleIncomingMessage: Message appended to array. Count: \(messageCountBeforeAdd) -> \(messages.count)")
        
        // Clear error when messages are successfully received
        if loadError != nil {
            loadError = nil
            //print("✅ Error cleared - messages received successfully")
        }
        
        // Clear isRefreshing flag when new messages arrive during refresh
        if isRefreshing {
            // Check if we got a new message (different from last before refresh)
            if let lastMessageId = messages.last?.id, lastMessageId != lastMessageIdBeforeRefresh {
                isRefreshing = false
                lastMessageIdBeforeRefresh = nil
                //print("✅ Pull-to-refresh completed: new messages received")
            } else if messageCountBeforeAdd == 0 && messages.count > 0 {
                // If we had no messages and now we have some, refresh is complete
                isRefreshing = false
                lastMessageIdBeforeRefresh = nil
                //print("✅ Pull-to-refresh completed: messages loaded")
            }
        }
        
        //print("📊 Message added to array:")
        //print("   Count before: \(messageCountBeforeAdd)")
        //print("   Count after: \(messages.count)")
        
        print("🔄 ChatRoomViewModel.handleIncomingMessage: Sorting messages by timestamp")
        let countBeforeSort = messages.count
        
        // Match TypeScript: Sort by timestamp (messages should be in chronological order)
        messages.sort { msg1, msg2 in
            let ts1 = msg1.timestamp ?? 0
            let ts2 = msg2.timestamp ?? 0
            return ts1 < ts2
        }
        
        print("   Messages sorted. Count: \(countBeforeSort) -> \(messages.count)")
        
        // CRITICAL FIX: After sorting, remove duplicates (keep the first occurrence)
        // This is especially important when loading older history where messages might be added multiple times
        print("🔄 ChatRoomViewModel.handleIncomingMessage: Deduplicating messages after sort")
        let countBeforeDedup = messages.count
        var seenIds = Set<String>()
        var duplicatesRemoved: [String] = []
        
        messages = messages.filter { msg in
            let id = msg.id
            if seenIds.contains(id) {
                duplicatesRemoved.append(id)
                print("   ⚠️ Removing duplicate message after sort: ID='\(id)', body='\(msg.body.prefix(30))'")
                return false
            }
            seenIds.insert(id)
            return true
        }
        
        if !duplicatesRemoved.isEmpty {
            print("   Removed \(duplicatesRemoved.count) duplicate(s): \(duplicatesRemoved.prefix(5))")
        }
        print("   Messages deduplicated. Count: \(countBeforeDedup) -> \(messages.count)")
        
        if messages.count != messageCountBeforeAdd {
            print("📊 ChatRoomViewModel.handleIncomingMessage: Final message count changed during processing")
            print("   Started with: \(messageCountBeforeAdd)")
            print("   After add: \(countBeforeSort)")
            print("   After sort: \(countBeforeSort)")
            print("   After dedup: \(messages.count)")
            print("   Net change: \(messages.count - messageCountBeforeAdd)")
        }
        
        // Update room's messages array
        room.messages = messages
        // Update the published room property to trigger UI updates
        self.room = room
        
        print("💾 ChatRoomViewModel.handleIncomingMessage: Saving all messages to cache. Total: \(messages.count)")
        if messages.count > 0 {
            print("   First message ID: '\(messages.first?.id ?? "nil")', timestamp: \(messages.first?.timestamp?.description ?? "nil")")
            print("   Last message ID: '\(messages.last?.id ?? "nil")', timestamp: \(messages.last?.timestamp?.description ?? "nil")")
            print("   Last 5 message IDs: \(messages.map { $0.id }.suffix(5))")
        }
        
        // Save messages to cache
        MessageCache.shared.saveMessages(messages, forRoomJID: room.jid)
        print("✅ ChatRoomViewModel.handleIncomingMessage: Messages saved to cache")
        
        // Run cache maintenance after history/realtime updates to keep cache size optimized
        MessageCache.shared.cleanupIfNeeded()
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🟢 ChatRoomViewModel.handleIncomingMessage: COMPLETE")
        print("   Final message count: \(messages.count)")
        print("   Message ID: '\(message.id)'")
        print("   Action taken: \(messages.count > messageCountBeforeAdd ? "ADDED" : messages.count < messageCountBeforeAdd ? "REMOVED (dedup)" : "UPDATED")")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        // Якщо це pull-to-refresh і з'явилося нове повідомлення, скидаємо прапорець
        // This is handled in the message append logic above, so we don't need duplicate logic here
        
        //print("✅ Message with body '\(message.body.prefix(30))...' added to room with id '\(room.jid)'")
        //print("   Final messages count: \(messages.count)")
        //print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        // Track received messages for initial load
        // Only count if we're currently loading and this is a history message (not real-time)
        if isLoading && expectedMessageCount > 0 {
            receivedMessageCount += 1
            //print("📊 Received \(receivedMessageCount)/\(expectedMessageCount) messages")
            
            // Check if we've received all expected messages
            // Also check if we've received at least the expected count or if 3 seconds have passed
            let timeSinceStart = loadingStartTime.map { Date().timeIntervalSince($0) } ?? 0
            
            if receivedMessageCount >= expectedMessageCount || timeSinceStart >= 3.0 {
                // All messages received or timeout reached, hide loader
                isLoading = false
                messagesLoaded = true
                loadingStartTime = nil
                
                // Clear error if we received messages successfully
                if receivedMessageCount > 0 {
                    loadError = nil
                }
                
                //print("✅ Loading complete. Received \(receivedMessageCount) messages. Hiding loader.")
            }
        } else {
            // If we are loading more (scrolling up), debounced reset of isLoadingMore
            if isLoadingMore {
                // Track that we received a message during history load
                historyLoadReceivedCount += 1
                let timeSinceStart = historyLoadStartTime.map { Date().timeIntervalSince($0) } ?? 0
                
                // Reset isLoadingMore if we've received enough messages or waited long enough
                if historyLoadReceivedCount >= pageSize || timeSinceStart >= 2.0 {
                    isLoadingMore = false
                    scrollPositionBeforeLoad = nil
                    historyLoadReceivedCount = 0
                    historyLoadStartTime = nil
                    
                    let currentCount = messages.count
                    let loadedCount = currentCount - messagesCountBeforeLoad
                    
                    print("✅ ChatRoomViewModel.handleIncomingMessage: Reset isLoadingMore after receiving \(historyLoadReceivedCount) messages during history load")
                    print("   📊 Message count before load: \(messagesCountBeforeLoad)")
                    print("   📊 Message count after load: \(currentCount)")
                    print("   📊 Messages loaded: \(loadedCount)")
                    
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
                } else {
                    // Debounced reset - wait for more messages or timeout
                    loadingMoreTask?.cancel()
                    loadingMoreTask = Task {
                        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second silence = batch done
                        if isLoadingMore {
                            isLoadingMore = false
                            scrollPositionBeforeLoad = nil
                            historyLoadReceivedCount = 0
                            historyLoadStartTime = nil
                            
                            let currentCount = messages.count
                            let loadedCount = currentCount - messagesCountBeforeLoad
                            
                            print("✅ ChatRoomViewModel.handleIncomingMessage: Reset isLoadingMore after 1s silence during history load")
                            print("   📊 Message count before load: \(messagesCountBeforeLoad)")
                            print("   📊 Message count after load: \(currentCount)")
                            print("   📊 Messages loaded: \(loadedCount)")
                            
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
        print("📤 ChatRoomViewModel.sendMedia: Called with type: \(type), size: \(data.count) bytes")
        
        guard let user = UserStore.shared.currentUser else {
            print("❌ ChatRoomViewModel.sendMedia: No current user")
            return
        }
        
        // Generate unique message ID
        let messageId = "send-media-message-\(Int64(Date().timeIntervalSince1970 * 1000))"
        
        Task {
            do {
                // Convert HEIC to JPEG if needed
                var finalData = data
                var finalMimeType = type
                var finalFileName = "media_\(Int64(Date().timeIntervalSince1970 * 1000))"
                
                #if os(iOS)
                if type == "image/heic" || type == "image/heif" {
                    print("🔄 ChatRoomViewModel.sendMedia: Converting HEIC to JPEG...")
                    if let uiImage = UIImage(data: data) {
                        if let jpegData = uiImage.jpegData(compressionQuality: 0.8) {
                            finalData = jpegData
                            finalMimeType = "image/jpeg"
                            finalFileName = "\(finalFileName).jpg"
                            print("✅ ChatRoomViewModel.sendMedia: Converted HEIC to JPEG (\(data.count) -> \(jpegData.count) bytes)")
                        } else {
                            print("❌ ChatRoomViewModel.sendMedia: Failed to convert HEIC to JPEG")
                            return
                        }
                    } else {
                        print("❌ ChatRoomViewModel.sendMedia: Failed to create UIImage from HEIC data")
                        return
                    }
                } else {
                    // Determine file extension from MIME type
                    let fileExtension: String
                    if type.starts(with: "image/") {
                        if type.contains("png") {
                            fileExtension = "png"
                        } else if type.contains("gif") {
                            fileExtension = "gif"
                        } else {
                            fileExtension = "jpg"
                        }
                    } else if type.starts(with: "video/") {
                        fileExtension = "mp4"
                    } else if type.contains("pdf") {
                        fileExtension = "pdf"
                    } else {
                        fileExtension = "bin"
                    }
                    finalFileName = "\(finalFileName).\(fileExtension)"
                }
                #else
                // For macOS, determine file extension from MIME type
                let fileExtension: String
                if type.starts(with: "image/") {
                    if type.contains("png") {
                        fileExtension = "png"
                    } else if type.contains("gif") {
                        fileExtension = "gif"
                    } else {
                        fileExtension = "jpg"
                    }
                } else if type.starts(with: "video/") {
                    fileExtension = "mp4"
                } else if type.contains("pdf") {
                    fileExtension = "pdf"
                } else {
                    fileExtension = "bin"
                }
                finalFileName = "\(finalFileName).\(fileExtension)"
                #endif
                
                print("📤 ChatRoomViewModel.sendMedia: Final filename: \(finalFileName), MIME type: \(finalMimeType), size: \(finalData.count) bytes")
                
                // Upload file to server
                guard let token = UserStore.shared.token else {
                    print("❌ ChatRoomViewModel.sendMedia: No authentication token")
                    return
                }
                
                print("📤 ChatRoomViewModel.sendMedia: Uploading file \(finalFileName) (\(finalData.count) bytes) to server...")
                let uploadResponse = try await AuthAPI.uploadFile(
                    fileData: finalData,
                    fileName: finalFileName,
                    mimeType: finalMimeType,
                    token: token
                )
                
                guard let uploadResult = uploadResponse.results.first else {
                    print("❌ ChatRoomViewModel.sendMedia: No upload result in response")
                    return
                }
                
                guard let resultId = uploadResult._id,
                      let resultFilename = uploadResult.filename,
                      let resultMimetype = uploadResult.mimetype,
                      let resultSize = uploadResult.size,
                      let resultLocation = uploadResult.location,
                      let resultCreatedAt = uploadResult.createdAt else {
                    print("❌ ChatRoomViewModel.sendMedia: Missing required fields in upload result")
                    print("   _id: \(uploadResult._id ?? "nil")")
                    print("   filename: \(uploadResult.filename ?? "nil")")
                    print("   mimetype: \(uploadResult.mimetype ?? "nil")")
                    print("   size: \(uploadResult.size?.description ?? "nil")")
                    print("   location: \(uploadResult.location ?? "nil")")
                    print("   createdAt: \(uploadResult.createdAt ?? "nil")")
                    return
                }
                
                print("✅ ChatRoomViewModel.sendMedia: File uploaded successfully")
                print("   Location: \(resultLocation)")
                print("   ID: \(resultId)")
                print("   Filename: \(resultFilename)")
                print("   Size: \(resultSize) bytes")
                
                // Create media message data
                // Convert size from Int to String for MediaMessageData
                // Convert expiresAt from Int to String (0 means no expiration, or timestamp)
                let expiresAtString: String?
                if let expiresAt = uploadResult.expiresAt {
                    expiresAtString = expiresAt == 0 ? nil : String(expiresAt)
                } else {
                    expiresAtString = nil
                }
                
                let mediaData = MediaMessageData(
                    firstName: user.firstName ?? "",
                    lastName: user.lastName ?? "",
                    walletAddress: user.walletAddress ?? "",
                    chatName: room.title,
                    createdAt: resultCreatedAt,
                    fileName: resultFilename,
                    userId: uploadResult.userId ?? user.id,
                    isVisible: uploadResult.isVisible ?? true,
                    userAvatar: user.profileImage,
                    expiresAt: expiresAtString, // Convert Int to String or nil
                    location: resultLocation,
                    locationPreview: uploadResult.locationPreview,
                    mimetype: resultMimetype,
                    originalName: uploadResult.originalname ?? resultFilename,
                    ownerKey: uploadResult.ownerKey,
                    size: String(resultSize), // Convert Int to String
                    duration: uploadResult.duration,
                    updatedAt: uploadResult.updatedAt,
                    attachmentId: resultId,
                    roomJid: room.jid
                )
                
                print("📤 ChatRoomViewModel.sendMedia: Sending media message via XMPP to room: \(room.jid)")
                
                // Send media message via XMPP
                client.operations.sendMediaMessage(
                    roomJID: room.jid,
                    data: mediaData,
                    id: messageId
                )
                
                print("✅ ChatRoomViewModel.sendMedia: Media message sent via XMPP")
                
            } catch {
                print("❌ ChatRoomViewModel.sendMedia: Error - \(error.localizedDescription)")
                print("   Error details: \(error)")
            }
        }
    }
    
    public func editMessage(_ messageId: String, newText: String) {
        print("✏️ ChatRoomViewModel: Editing message \(messageId) with new text: '\(newText)'")
        print("   Current messages count: \(messages.count)")
        
        // Send edit request via XMPP
        client.operations.editMessage(
            chatId: room.jid,
            messageId: messageId,
            text: newText
        )
        
        // Update local message optimistically
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            print("✅ ChatRoomViewModel: Found message at index \(index), updating optimistically")
            var updatedMessage = messages[index]
            // Create updated message with new body
            let newMessage = Message(
                id: updatedMessage.id,
                user: updatedMessage.user,
                date: updatedMessage.date,
                body: newText,
                roomJid: updatedMessage.roomJid,
                key: updatedMessage.key,
                coinsInMessage: updatedMessage.coinsInMessage,
                numberOfReplies: updatedMessage.numberOfReplies,
                isSystemMessage: updatedMessage.isSystemMessage,
                isMediafile: updatedMessage.isMediafile,
                locationPreview: updatedMessage.locationPreview,
                mimetype: updatedMessage.mimetype,
                location: updatedMessage.location,
                pending: updatedMessage.pending,
                timestamp: updatedMessage.timestamp,
                showInChannel: updatedMessage.showInChannel,
                activeMessage: updatedMessage.activeMessage,
                isReply: updatedMessage.isReply,
                isDeleted: updatedMessage.isDeleted,
                mainMessage: updatedMessage.mainMessage,
                reply: updatedMessage.reply,
                reaction: updatedMessage.reaction,
                fileName: updatedMessage.fileName,
                translations: updatedMessage.translations,
                langSource: updatedMessage.langSource,
                originalName: updatedMessage.originalName,
                size: updatedMessage.size,
                xmppId: updatedMessage.xmppId,
                xmppFrom: updatedMessage.xmppFrom,
                waveForm: updatedMessage.waveForm
            )
            messages[index] = newMessage
            room.messages = messages
            
            print("✅ ChatRoomViewModel: Message updated optimistically. Total messages: \(messages.count)")
            print("   Message ID: \(newMessage.id), Body: '\(newMessage.body)'")
            
            // CRITICAL: Save updated message to cache immediately so it persists even if connection is lost
            MessageCache.shared.saveMessages(messages, forRoomJID: room.jid)
            print("💾 ChatRoomViewModel: Saved edited message to cache")
            
            // Update RoomStore
            var updates = PartialMessageUpdate()
            updates.body = newText
            RoomStore.shared.updateMessage(
                roomJID: room.jid,
                messageId: messageId,
                updates: updates
            )
        } else {
            print("❌ ChatRoomViewModel: Message with id \(messageId) not found in messages array!")
            print("   Available message IDs: \(messages.map { $0.id }.prefix(5))")
        }
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
                        //print("❌ ChatRoomViewModel.resendMessage: Error loading media - \(error.localizedDescription)")
                    }
                }
            }
        } else {
            // Resend as text message
            sendMessage(message.body)
        }
    }
    
    public func deleteMessage(_ messageId: String) {
        print("🗑️ ChatRoomViewModel: Deleting message \(messageId)")
        print("   Current messages count: \(messages.count)")
        
        // Send delete request via XMPP
        client.operations.deleteMessage(room: room.jid, msgId: messageId)
        
        // Match TypeScript EXACTLY: deleteRoomMessage filters out the message completely
        // From roomsSlice.ts lines 109-111:
        // state.rooms[roomJID].messages = state.rooms[roomJID].messages.filter(
        //   (message) => message.id !== messageId
        // );
        // Optimistically remove message from array immediately
        let messagesBeforeDelete = messages.count
        messages = messages.filter { $0.id != messageId }
        room.messages = messages
        
        print("✅ ChatRoomViewModel.deleteMessage: Message removed optimistically")
        print("   Messages before: \(messagesBeforeDelete), after: \(messages.count)")
        
        // CRITICAL: Save updated messages array to cache immediately
        MessageCache.shared.saveMessages(messages, forRoomJID: room.jid)
        print("💾 ChatRoomViewModel.deleteMessage: Saved updated messages to cache")
        
        // Update RoomStore (if needed for other parts of the app)
        RoomStore.shared.deleteMessage(roomJID: room.jid, messageId: messageId)
    }
    
    /// Add reaction to a message
    public func addReaction(messageId: String, emoji: String) {
        // Get current user info
        guard let user = UserStore.shared.currentUser else {
            //print("❌ Cannot add reaction: user not found")
            return
        }
        
        let firstName = user.firstName ?? "User"
        let lastName = user.lastName ?? "Name"
        
        // Get current reactions for this message to toggle
        let currentMessage = messages.first { $0.id == messageId }
        let currentReactions = currentMessage?.reaction?[currentUserId]?.emoji ?? []
        
        // Toggle reaction: if already reacted with this emoji, remove it; otherwise add it
        var newReactions = currentReactions
        if let index = newReactions.firstIndex(of: emoji) {
            newReactions.remove(at: index)
        } else {
            newReactions.append(emoji)
        }
        
        // Create reaction data
        let reactionData = ReactionData(firstName: firstName, lastName: lastName)
        
        // Send reaction via XMPP
        client.operations.sendMessageReaction(
            messageId: messageId,
            roomJid: room.jid,
            reactionsList: newReactions,
            data: reactionData
        )
        
        // Update local state optimistically
        // Get JID from client - avoid accessing xmppStream directly due to ambiguity
        let fromJid: String = {
            // Access via reflection or use a helper method
            // For now, return empty string as JID is not critical for reactions
            return ""
        }()
        let dataDict: [String: String] = [
            "senderFirstName": firstName,
            "senderLastName": lastName
        ]
        
        RoomStore.shared.setReactions(
            roomJID: room.jid,
            messageId: messageId,
            reactions: newReactions,
            from: fromJid,
            data: dataDict
        )
        
        // Update local messages array
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            var updatedMessage = messages[index]
            if updatedMessage.reaction == nil {
                updatedMessage.reaction = [:]
            }
            let fromId = fromJid.components(separatedBy: "@").first ?? fromJid
            if newReactions.isEmpty {
                updatedMessage.reaction?.removeValue(forKey: fromId)
            } else {
                updatedMessage.reaction?[fromId] = ReactionMessage(emoji: newReactions, data: dataDict)
            }
            messages[index] = updatedMessage
            room.messages = messages
            
            // CRITICAL: Save updated message to cache immediately
            MessageCache.shared.saveMessages(messages, forRoomJID: room.jid)
        }
    }
    
    public func cancelEdit() {
        isEditing = false
        editText = nil
        editMessageId = nil
    }
    
    private var typingTimer: Task<Void, Never>?
    private var stopTypingTimer: Task<Void, Never>?
    private var isTypingActive: Bool = false
    
    public func startTyping() {
        // Cancel any existing stop typing timer
        stopTypingTimer?.cancel()
        stopTypingTimer = nil
        
        // If already typing, don't send again
        guard !isTypingActive else { return }
        
        // Cancel previous typing timer if exists
        typingTimer?.cancel()
        
        // Debounce: Only send after 1 second of typing
        typingTimer = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            // Check if task was cancelled
            guard !Task.isCancelled else { return }
            
            // Get current user info
            guard let user = UserStore.shared.currentUser else { return }
            let fullName = "\(user.firstName ?? "") \(user.lastName ?? "")".trimmingCharacters(in: .whitespaces)
            
            if !fullName.isEmpty {
                //print("⌨️ ChatRoomViewModel: Sending typing indicator")
                client.operations.sendTypingRequest(
                    chatId: room.jid,
                    fullName: fullName,
                    start: true
                )
                isTypingActive = true
            }
        }
        
        // Auto-stop typing after 3 seconds of inactivity
        stopTypingTimer = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            guard !Task.isCancelled else { return }
            stopTyping()
        }
    }
    
    public func stopTyping() {
        // Cancel typing timer
        typingTimer?.cancel()
        typingTimer = nil
        
        // Cancel stop typing timer
        stopTypingTimer?.cancel()
        stopTypingTimer = nil
        
        // Only send stop if we were actually typing
        guard isTypingActive else { return }
        
        // Get current user info
        guard let user = UserStore.shared.currentUser else { return }
        let fullName = "\(user.firstName ?? "") \(user.lastName ?? "")".trimmingCharacters(in: .whitespaces)
        
        if !fullName.isEmpty {
            //print("⌨️ ChatRoomViewModel: Sending stop typing indicator")
            client.operations.sendTypingRequest(
                chatId: room.jid,
                fullName: fullName,
                start: false
            )
            isTypingActive = false
        }
    }
}

