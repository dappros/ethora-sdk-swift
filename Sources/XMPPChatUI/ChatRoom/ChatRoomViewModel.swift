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
    internal var historyRetryAttempts: Int = 0
    internal let maxHistoryRetryAttempts: Int = 3
    
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
}
