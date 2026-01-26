//
//  MessageListViewModel.swift
//  XMPPChatUI
//
//  ViewModel for Message List with pagination support
//  Replicates logic from Web MessageList.tsx
//

import Foundation
import Combine
import XMPPChatCore

#if canImport(SwiftUI)
import SwiftUI
#endif

@MainActor
public class MessageListViewModel: ObservableObject {
    // MARK: - Published Properties
    
    /// All messages in the list (sorted chronologically)
    @Published public var messages: [Message] = []
    
    /// Whether more messages are currently being loaded
    @Published public var isLoadingMore: Bool = false
    
    /// Whether all history has been loaded (no more messages to fetch)
    @Published public var isHistoryComplete: Bool = false
    
    /// Whether initial messages are loading
    @Published public var isLoading: Bool = false
    
    // MARK: - Private Properties
    
    /// Scroll position before loading more messages (for scroll anchoring)
    private var scrollParamsBeforeLoad: (top: CGFloat, height: CGFloat)?
    
    /// Message count before loading more (to detect when new messages arrive)
    private var messageCountBeforeLoad: Int = 0
    
    /// Get previous message count (for scroll position restoration)
    public func getPreviousMessageCount() -> Int? {
        return messageCountBeforeLoad > 0 ? messageCountBeforeLoad : nil
    }
    
    /// Debounce timer for scroll detection
    private var scrollDebounceTask: Task<Void, Never>?
    
    /// Reference to the ChatRoomViewModel for loading messages
    private weak var chatRoomViewModel: ChatRoomViewModel?
    
    /// Room JID this list is for
    public let roomJID: String
    
    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    public init(roomJID: String, chatRoomViewModel: ChatRoomViewModel? = nil) {
        self.roomJID = roomJID
        self.chatRoomViewModel = chatRoomViewModel
        
        setupObservers()
        setupChatRoomViewModelObserver()
    }
    
    /// Setup observer for ChatRoomViewModel changes
    private func setupChatRoomViewModelObserver() {
        // Observe ChatRoomViewModel's messages and loading state
        if let chatRoomViewModel = chatRoomViewModel {
            // Update messages when ChatRoomViewModel's messages change
            chatRoomViewModel.$messages
                .receive(on: DispatchQueue.main)
                .sink { [weak self] newMessages in
                    self?.messages = newMessages
                }
                .store(in: &cancellables)
            
            // Update loading state
            chatRoomViewModel.$isLoadingMore
                .receive(on: DispatchQueue.main)
                .sink { [weak self] isLoading in
                    self?.isLoadingMore = isLoading
                }
                .store(in: &cancellables)
            
            // Update history complete state
            chatRoomViewModel.$room
                .map { $0.historyComplete ?? false }
                .receive(on: DispatchQueue.main)
                .sink { [weak self] complete in
                    self?.isHistoryComplete = complete
                }
                .store(in: &cancellables)
        }
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        // Observe room messages updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRoomMessagesUpdated(_:)),
            name: NSNotification.Name("RoomMessagesUpdated"),
            object: nil
        )
        
        // Observe history complete notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHistoryComplete(_:)),
            name: NSNotification.Name("XMPPHistoryComplete"),
            object: nil
        )
        
        // Observe messages loaded (for scroll position restoration)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMessagesLoaded(_:)),
            name: NSNotification.Name("MessagesLoaded"),
            object: nil
        )
    }
    
    // MARK: - Notification Handlers
    
    @objc private func handleRoomMessagesUpdated(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let notificationRoomJID = userInfo["roomJID"] as? String else {
            return
        }
        
        // Only handle updates for this room
        let normalizedNotificationRoom = notificationRoomJID.components(separatedBy: "/").first ?? notificationRoomJID
        let normalizedCurrentRoom = roomJID.components(separatedBy: "/").first ?? roomJID
        
        guard normalizedNotificationRoom == normalizedCurrentRoom else {
            return
        }
        
        // Update messages from ChatRoomViewModel if available
        if let chatRoomViewModel = chatRoomViewModel {
            messages = chatRoomViewModel.messages
        }
    }
    
    @objc private func handleHistoryComplete(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let notificationRoomJID = userInfo["roomJID"] as? String,
              let historyComplete = userInfo["historyComplete"] as? Bool else {
            return
        }
        
        // Only handle for this room
        let normalizedNotificationRoom = notificationRoomJID.components(separatedBy: "/").first ?? notificationRoomJID
        let normalizedCurrentRoom = roomJID.components(separatedBy: "/").first ?? roomJID
        
        guard normalizedNotificationRoom == normalizedCurrentRoom else {
            return
        }
        
        isHistoryComplete = historyComplete
    }
    
    @objc private func handleMessagesLoaded(_ notification: Notification) {
        // Messages finished loading - prepare for scroll position restoration
        guard let userInfo = notification.userInfo else { return }
        
        let oldCount = userInfo["oldCount"] as? Int ?? 0
        let newCount = userInfo["newCount"] as? Int ?? messages.count
        
        // CRITICAL: Reset isLoadingMore after messages are loaded
        // This allows continuous loading to work (matches Web: isLoadingMore.current = false in finally block)
        // The ChatRoomViewModel resets it after 1 second debounce, but we also reset here to ensure it's cleared
        if newCount > oldCount {
            // Messages were loaded - reset loading flag after a short delay to allow scroll restoration
            // This matches Web: isLoadingMore.current = false in the finally block
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                self.isLoadingMore = false
            }
        } else {
            // No new messages - reset immediately
            isLoadingMore = false
        }
        
        // If messages were added (prepended), we need to restore scroll position
        if newCount > oldCount && scrollParamsBeforeLoad != nil {
            // Post notification to trigger scroll position restoration in view
            NotificationCenter.default.post(
                name: NSNotification.Name("RestoreScrollPosition"),
                object: nil,
                userInfo: [
                    "oldHeight": scrollParamsBeforeLoad!.height,
                    "oldTop": scrollParamsBeforeLoad!.top
                ]
            )
            
            // Don't clear scroll params here - they'll be cleared after restoration
            // This allows recursive loading check to work properly
        } else if newCount == oldCount {
            // No new messages were loaded - clear params
            scrollParamsBeforeLoad = nil
        }
    }
    
    // MARK: - Public Methods
    
    /// Fetch history (load more messages)
    /// Matches Web: loadMoreMessages(beforeId: String)
    /// Checks both !isLoadingMore AND !historyComplete before execution
    public func fetchHistory() {
        // CRITICAL: Check both conditions (matches Web: !isLoadingMore && !historyComplete)
        guard !isLoadingMore else {
            return
        }
        guard !isHistoryComplete else {
            return
        }
        
        // Get the ID of the oldest message currently displayed
        // Skip "delimiter-new" if present (matches Web logic)
        // Web: const [firstMessage, secondMessage] = memoizedMessages;
        //      const firstMessageId = firstMessage?.id === 'delimiter-new' ? secondMessage?.id : firstMessage?.id;
        let firstMessage = messages.first(where: { $0.id != "delimiter-new" }) ?? messages.first
        
        guard let message = firstMessage else {
            // No messages to use as reference
            return
        }
        
        // Convert message ID to Int64 (matches Web: Number(firstMessageId))
        let beforeId: Int64? = {
            // Try to convert message.id directly to Int64
            if let numericId = Int64(message.id) {
                return numericId
            }
            
            // If message.id is not numeric, try timestamp
            if let timestamp = message.timestamp {
                return timestamp
            }
            
            // Last resort: convert date to timestamp (milliseconds)
            return Int64(message.date.timeIntervalSince1970 * 1000)
        }()
        
        guard let before = beforeId else {
            return
        }
        
        // Save scroll position before loading (for scroll anchoring)
        // This will be used to maintain scroll position after messages are prepended
        // Note: Scroll position should already be saved by the view before calling fetchHistory()
        // But we ensure it's saved here as a fallback
        if scrollParamsBeforeLoad == nil {
            // If not already saved, this is a fallback (shouldn't happen in normal flow)
            messageCountBeforeLoad = messages.count
        }
        
        isLoadingMore = true
        messageCountBeforeLoad = messages.count
        
        // Call loadMoreMessages on ChatRoomViewModel
        // Web: loadMoreMessages(firstMessage.roomJid, 30, Number(firstMessageId))
        chatRoomViewModel?.loadMoreMessages(max: 30, beforeTimestamp: before)
        
        // CRITICAL: Set timeout to reset loading state (safety timeout)
        // This ensures isLoadingMore is reset even if notification doesn't fire
        // But we rely on ChatRoomViewModel's debounced reset (1 second after messages stop arriving)
        Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds safety timeout
            if isLoadingMore {
                isLoadingMore = false
                // Don't clear scroll params here - they're needed for restoration
            }
        }
    }
    
    /// Save scroll position before loading more messages
    /// Called by the view when scroll position is detected
    public func saveScrollPosition(top: CGFloat, height: CGFloat) {
        scrollParamsBeforeLoad = (top: top, height: height)
        messageCountBeforeLoad = messages.count
    }
    
    /// Get scroll position info for restoration
    /// Returns the old scroll top and height for calculating new scroll position
    public func getScrollPositionInfo() -> (top: CGFloat, height: CGFloat)? {
        return scrollParamsBeforeLoad
    }
    
    /// Clear scroll position info after restoration
    public func clearScrollPositionInfo() {
        scrollParamsBeforeLoad = nil
        messageCountBeforeLoad = 0
    }
    
    /// Save scroll position before load (internal method)
    private func saveScrollPositionBeforeLoad() {
        // This will be set by the view when it detects scroll position
        // The view should call saveScrollPosition(top:height:) before calling fetchHistory()
    }
    
    /// Update messages from external source (e.g., ChatRoomViewModel)
    public func updateMessages(_ newMessages: [Message]) {
        messages = newMessages
    }
    
    /// Update loading state
    public func setLoading(_ loading: Bool) {
        isLoading = loading
    }
    
    /// Update loading more state
    public func setLoadingMore(_ loading: Bool) {
        isLoadingMore = loading
        // Don't clear scroll params here - they will be cleared after scroll position is restored
        // Clearing them here would prevent proper scroll restoration and recursive loading checks
    }
    
    /// Update history complete state
    public func setHistoryComplete(_ complete: Bool) {
        isHistoryComplete = complete
    }
    
    /// Set ChatRoomViewModel reference (can be called after initialization)
    public func setChatRoomViewModel(_ viewModel: ChatRoomViewModel) {
        self.chatRoomViewModel = viewModel
        setupChatRoomViewModelObserver()
    }
}
