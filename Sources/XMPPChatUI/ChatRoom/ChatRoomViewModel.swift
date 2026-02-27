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
    
    internal let client: XMPPClient
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
    
    internal var cancellables = Set<AnyCancellable>()
    internal var messagesLoaded: Bool = false // Track if messages have been loaded
    internal var savedScrollPosition: String? // Track last scroll position (message ID)
    internal var isFirstLoad: Bool = true // Track if this is the first time loading messages
    internal var scrollPositionRestored: Bool = false // Track if we've already restored scroll position
    internal var expectedMessageCount: Int = 0 // Track how many messages we expect to receive
    internal var receivedMessageCount: Int = 0 // Track how many messages we've received in current load
    internal var loadingStartTime: Date? // Track when loading started for timeout
    internal var loadingMoreTask: Task<Void, Never>? // Task to handle loading more timeout/reset
    internal var historyLoadReceivedCount: Int = 0 // Track messages received during history load (including duplicates)
    internal var historyLoadStartTime: Date? // Track when history load started
    
    // Telegram-like scroll position maintenance
    internal var scrollPositionBeforeLoad: (messageId: String, messageIndex: Int)? = nil
    internal var messagesCountBeforeLoad: Int = 0
    internal var lastMessageIdBeforeRefresh: String?
    
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
    
    
    // MARK: - Lifecycle and State Management

    // Remaining methods have been moved to extension files:
    // - ChatRoomViewModel+Observers.swift: setupObservers and notification handlers
    // - ChatRoomViewModel+History.swift: History loading and scrolling management
    // - ChatRoomViewModel+Messages.swift: handleIncomingMessage
    // - ChatRoomViewModel+Actions.swift: Messaging actions (send, edit, delete, react, typing)
    // - ChatRoomViewModel+XMPP.swift: XMPP delegate methods
    
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
            objectWillChange.send()
        } else {
            // Wait a bit to ensure XMPP connection is stable before loading
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                
                guard client.checkOnline() else {
                    return
                }
                
                loadMessages()
            }
        }
    }

    /// Mark that scroll position has been restored
    public func markScrollPositionRestored() {
        scrollPositionRestored = true
    }
    
    /// Check if scroll position has been restored
    public var hasRestoredScrollPosition: Bool {
        return scrollPositionRestored
    }
    
    /// Get the saved scroll position
    public func getScrollPosition() -> String? {
        return nil
    }
    
    /// Check if we should scroll to bottom
    public func shouldScrollToBottom() -> Bool {
        if isFirstLoad {
            isFirstLoad = false
            return true
        }
        return false
    }
}
