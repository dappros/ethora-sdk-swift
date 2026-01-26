//
//  MessageListView.swift
//  XMPPChatUI
//
//  SwiftUI Message List View with pagination and scroll anchoring
//  Replicates logic from Web MessageList.tsx
//
//  USAGE:
//  ------
//  let messageListViewModel = MessageListViewModel(
//      roomJID: room.jid,
//      chatRoomViewModel: chatRoomViewModel
//  )
//
//  MessageListView(
//      viewModel: messageListViewModel,
//      currentUserId: currentUserId,
//      currentUserXmppUsername: currentUserXmppUsername,
//      config: config
//  )
//
//  FEATURES:
//  --------
//  - Automatic "Load More Messages" when scrolling near top (~150px threshold)
//  - Scroll position anchoring: maintains view position when messages are prepended
//  - Supports both SwiftUI ScrollView and UIKit UIScrollView (for precise control)
//  - Integrates with ChatRoomViewModel for message loading
//

import SwiftUI
import XMPPChatCore

// MARK: - Scroll Metrics Tracking

/// Scroll metrics for tracking scroll position (matches Web getScrollParams)
struct MessageScrollMetrics: Equatable {
    let scrollTop: CGFloat
    let scrollHeight: CGFloat
    let clientHeight: CGFloat
}

struct MessageScrollMetricsKey: PreferenceKey {
    static var defaultValue: MessageScrollMetrics = MessageScrollMetrics(
        scrollTop: 0,
        scrollHeight: 0,
        clientHeight: 0
    )
    
    static func reduce(value: inout MessageScrollMetrics, nextValue: () -> MessageScrollMetrics) {
        value = nextValue()
    }
}

// MARK: - Message List View

public struct MessageListView: View {
    // MARK: - Properties
    
    @ObservedObject var viewModel: MessageListViewModel
    @State private var scrollMetrics: MessageScrollMetrics = MessageScrollMetrics(
        scrollTop: 0,
        scrollHeight: 0,
        clientHeight: 0
    )
    @State private var scrollTop: CGFloat = 0
    @State private var scrollHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var previousContentHeight: CGFloat = 0
    @State private var scrollDebounceTask: Task<Void, Never>?
    
    /// Custom message view builder
    public var messageViewBuilder: ((Message, Bool) -> AnyView)?
    
    /// Configuration
    public let config: ChatConfig?
    
    /// Current user ID for determining message alignment
    public let currentUserId: String
    
    /// Current user XMPP username
    public let currentUserXmppUsername: String?
    
    /// Whether to use UIKit-based scroll view for precise scroll control
    /// Default: true (recommended for accurate scroll anchoring)
    public let useUIKitScrollView: Bool
    
    // MARK: - Initialization
    
    public init(
        viewModel: MessageListViewModel,
        currentUserId: String,
        currentUserXmppUsername: String? = nil,
        config: ChatConfig? = nil,
        messageViewBuilder: ((Message, Bool) -> AnyView)? = nil,
        useUIKitScrollView: Bool = true
    ) {
        self.viewModel = viewModel
        self.currentUserId = currentUserId
        self.currentUserXmppUsername = currentUserXmppUsername
        self.config = config
        self.messageViewBuilder = messageViewBuilder
        self.useUIKitScrollView = useUIKitScrollView
    }
    
    // MARK: - Body
    
    public var body: some View {
        if useUIKitScrollView {
            // Use UIKit-based scroll view for precise scroll control
            MessageListScrollView(
                viewModel: viewModel,
                currentUserId: currentUserId,
                currentUserXmppUsername: currentUserXmppUsername,
                config: config,
                messageViewBuilder: messageViewBuilder,
                scrollTop: $scrollTop,
                scrollHeight: $scrollHeight
            )
        } else {
            // Use SwiftUI ScrollView (simpler but less precise scroll control)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack( spacing: 8) {
                        // Loading indicator at top when loading more
                        if viewModel.isLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .padding()
                                Spacer()
                            }
                        }
                        
                        // Messages
                        ForEach(viewModel.messages) { message in
                            messageRow(message: message)
                                .id(message.id)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        // Track scroll position and content height
                        GeometryReader { geometry in
                            Color.clear
                                .preference(
                                    key: MessageScrollMetricsKey.self,
                                    value: MessageScrollMetrics(
                                        scrollTop: max(0, -geometry.frame(in: .named("messageScroll")).minY),
                                        scrollHeight: geometry.size.height,
                                        clientHeight: geometry.size.height
                                    )
                                )
                        }
                    )
                    .coordinateSpace(name: "messageScroll")
                }
                .onPreferenceChange(MessageScrollMetricsKey.self) { metrics in
                    handleScroll(metrics: metrics, proxy: proxy)
                }
                .onChange(of: viewModel.messages.count) { newCount in
                    // Handle scroll position restoration when messages are prepended
                    handleMessagesCountChanged(newCount: newCount, proxy: proxy)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RestoreScrollPosition"))) { notification in
                    // Restore scroll position after messages are loaded
                    restoreScrollPosition(notification: notification, proxy: proxy)
                }
            }
        }
    }
    
    // MARK: - Message Row
    
    @ViewBuilder
    private func messageRow(message: Message) -> some View {
        // Skip delimiter messages (they're handled separately in ChatRoomView)
        if message.id == "delimiter-new" {
            NewMessageLabel()
                .padding(.vertical, 8)
        } else {
            // Use custom message view builder if provided, otherwise use default
            if let customView = messageViewBuilder {
                customView(message, isCurrentUser(message))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Default message view
                MessageBubbleView(
                    message: message,
                    isUser: isCurrentUser(message),
                    showAvatar: true,
                    previousMessage: nil,
                    onLongPress: {},
                    onRetry: nil,
                    onReactionTap: { _ in },
                    onReply: {},
                    onEdit: nil,
                    onDelete: nil,
                    onReport: nil
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Check if message is from current user
    private func isCurrentUser(_ message: Message) -> Bool {
        let isCurrentUserById = message.user.id == currentUserId
        let isCurrentUserByXmpp: Bool = {
            guard let currentUserXmpp = currentUserXmppUsername,
                  let messageUserXmpp = message.user.xmppUsername else {
                return false
            }
            let normalizedCurrent = currentUserXmpp.lowercased().trimmingCharacters(in: .whitespaces)
            let normalizedMessage = messageUserXmpp.lowercased().trimmingCharacters(in: .whitespaces)
            return normalizedCurrent == normalizedMessage
        }()
        return isCurrentUserById || isCurrentUserByXmpp
    }
    
    // MARK: - Scroll Handling
    
    /// Handle scroll events (matches Web onScroll with debouncing)
    private func handleScroll(metrics: MessageScrollMetrics, proxy: ScrollViewProxy) {
        // Update scroll metrics
        scrollMetrics = metrics
        
        // Debounce scroll handling (matches Web: 50ms timeout)
        scrollDebounceTask?.cancel()
        scrollDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            
            guard !Task.isCancelled else { return }
            
            // Check if should load more messages (matches Web: checkIfLoadMoreMessages)
            checkIfLoadMoreMessages(metrics: metrics)
        }
    }
    
    /// Check if should load more messages (matches Web checkIfLoadMoreMessages)
    /// TypeScript: if (params.top >= 150 || isLoadingMore.current) return;
    /// Web also checks: !roomsList?.[chatJID]?.historyComplete
    private func checkIfLoadMoreMessages(metrics: MessageScrollMetrics) {
        // CRITICAL: Check both conditions (matches Web: !isLoadingMore && !historyComplete)
        guard !viewModel.isLoadingMore else { return }
        guard !viewModel.isHistoryComplete else { return }
        
        // Guard: Only trigger when near top (scrollTop < 150px) - matches TypeScript
        guard metrics.scrollTop < 150 else { return }
        
        // Save scroll position before loading (for scroll anchoring)
        // This matches Web: scrollParams.current = getScrollParams()
        viewModel.saveScrollPosition(top: metrics.scrollTop, height: metrics.scrollHeight)
        previousContentHeight = metrics.scrollHeight
        
        // Fetch history (load more messages)
        viewModel.fetchHistory()
    }
    
    /// Handle messages count change (for scroll position restoration)
    private func handleMessagesCountChanged(newCount: Int, proxy: ScrollViewProxy) {
        // Only restore if we have scroll params saved and messages increased
        guard let scrollInfo = viewModel.getScrollPositionInfo(),
              let previousCount = viewModel.getPreviousMessageCount(),
              newCount > previousCount else {
            return
        }
        
        // Wait for messages to render and content size to be calculated
        // SwiftUI needs time to layout the new content
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            // Double-check we still need restoration (might have been cleared)
            guard let currentScrollInfo = self.viewModel.getScrollPositionInfo() else {
                return
            }
            
            // Get updated scroll metrics after layout
            let updatedHeight = self.scrollMetrics.scrollHeight
            
            // Only restore if content height actually increased
            guard updatedHeight > currentScrollInfo.height else {
                self.viewModel.clearScrollPositionInfo()
                return
            }
            
            self.restoreScrollPositionAfterLoad(proxy: proxy, oldHeight: currentScrollInfo.height, oldTop: currentScrollInfo.top)
        }
    }
    
    /// Restore scroll position after messages are loaded
    /// Matches Web: newScrollTop = currentTop + (content.scrollHeight - previousHeight)
    /// SwiftUI version: Uses ScrollViewReader to scroll to the message that was at top
    private func restoreScrollPositionAfterLoad(
        proxy: ScrollViewProxy,
        oldHeight: CGFloat,
        oldTop: CGFloat
    ) {
        // Get current content height from metrics
        let currentHeight = scrollMetrics.scrollHeight
        
        // Only restore if content height has actually increased (new messages were prepended)
        guard currentHeight > oldHeight else {
            viewModel.clearScrollPositionInfo()
            return
        }
        
        // Calculate height difference (matches Web exactly)
        let heightDifference = currentHeight - oldHeight
        
        // In SwiftUI, we scroll to the message that was at the top before loading
        // This maintains visual continuity (the same message stays visible)
        if let firstMessage = viewModel.messages.first(where: { $0.id != "delimiter-new" }) ?? viewModel.messages.first {
            // Scroll to the first message (which was at the top before new messages were prepended)
            // Use no animation to prevent visual jump
            withAnimation(.none) {
                proxy.scrollTo(firstMessage.id, anchor: .top)
            }
            
            // Clear scroll position info after restoration
            viewModel.clearScrollPositionInfo()
            
            // CRITICAL: After scroll restoration, check if user is still at top
            // If yes and history is not complete, trigger another load (recursive check)
            // This matches Web behavior: continue loading until historyComplete or user scrolls away
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                // Update scroll metrics before checking
                // The scroll position should now be at the top after restoration
                self.checkIfShouldContinueLoading(proxy: proxy)
            }
        } else {
            viewModel.clearScrollPositionInfo()
        }
    }
    
    /// Check if should continue loading after messages are prepended
    /// Matches Web: recursive check after scroll restoration
    /// This ensures continuous loading until historyComplete or user scrolls away
    private func checkIfShouldContinueLoading(proxy: ScrollViewProxy) {
        // CRITICAL: Check both conditions (matches Web: !isLoadingMore && !historyComplete)
        guard !viewModel.isLoadingMore else { return }
        guard !viewModel.isHistoryComplete else { return }
        
        // Get current scroll position from metrics (should be updated after restoration)
        let scrollTop = scrollMetrics.scrollTop
        
        // If user is still at top (< 150px threshold), trigger another load
        // This ensures we keep loading until either:
        // 1. History is complete (historyComplete = true)
        // 2. User scrolls away from top (scrollTop >= 150)
        if scrollTop < 150 {
            // Save scroll position before loading again
            viewModel.saveScrollPosition(top: scrollTop, height: scrollMetrics.scrollHeight)
            
            // Trigger another load (this will continue until historyComplete)
            viewModel.fetchHistory()
        }
    }
    
    /// Restore scroll position from notification
    private func restoreScrollPosition(notification: Notification, proxy: ScrollViewProxy) {
        guard let userInfo = notification.userInfo,
              let oldHeight = userInfo["oldHeight"] as? CGFloat,
              let oldTop = userInfo["oldTop"] as? CGFloat else {
            return
        }
        
        restoreScrollPositionAfterLoad(proxy: proxy, oldHeight: oldHeight, oldTop: oldTop)
    }
}

// MARK: - Preview Support

#if DEBUG
struct MessageListView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = MessageListViewModel(roomJID: "test@conference.example.com")
        MessageListView(
            viewModel: viewModel,
            currentUserId: "user123",
            config: nil
        )
    }
}
#endif
