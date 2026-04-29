//
//  ChatRoomView.swift
//  XMPPChatUI
//
//  SwiftUI Chat Room component
//

import SwiftUI
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import WebKit
import AVKit
import PhotosUI
import UniformTypeIdentifiers
#endif
import XMPPChatCore
import AVFoundation

// Preference key for scroll metrics tracking (matches TypeScript getScrollParams)
struct ScrollMetrics: Equatable {
    let scrollTop: CGFloat
    let scrollHeight: CGFloat
    let clientHeight: CGFloat
}

struct ScrollMetricsKey: PreferenceKey {
    static var defaultValue: ScrollMetrics = ScrollMetrics(scrollTop: 0, scrollHeight: 0, clientHeight: 0)
    static func reduce(value: inout ScrollMetrics, nextValue: () -> ScrollMetrics) {
        value = nextValue()
    }
}

// Preference key for content height tracking
struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

public struct ChatRoomView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var viewModel: ChatRoomViewModel
    @State private var messageText: String = ""
    @State private var scrollOffset: CGFloat = 0
    @State private var showScrollButton: Bool = false
    @State private var newMessagesCount: Int = 0
    @State private var lastMessageCount: Int = 0
    @State private var scrollHeight: CGFloat = 0
    @State private var scrollTop: CGFloat = 0
    @State private var clientHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var isUserScrolledUp: Bool = false
    @State private var atBottom: Bool = true
    @State private var scrollProxy: ScrollViewProxy?
    /// `true` once we've pinned the initial scroll to the newest message.
    /// Until then we suppress `checkIfLoadMoreMessages`, because at layout
    /// time `scrollTop == 0` trips the "near-top" guard and would fire an
    /// unwanted older-history load right as the chat opens.
    @State private var hasPerformedInitialScroll: Bool = false
    /// While `true`, every `messages.count` / `isLoading` flip re-pins the
    /// scroll view to `bottom-anchor`. Flipped off the moment the user
    /// manually scrolls upward, re-armed on `onAppear`. Guarantees the chat
    /// opens at the bottom every time — including repeat opens and the
    /// race where MAM sends the last batch of messages a second or two
    /// after `onAppear` fires.
    @State private var pinToBottom: Bool = true
    /// iOS 17+ `scrollPosition(id:)` binding. SwiftUI re-anchors the
    /// ScrollView to whatever id this holds whenever content or viewport
    /// size changes — which is exactly what we need for the chat-on-open
    /// + keyboard-appears edge cases. Keep pointed at `bottom-anchor`
    /// until the user scrolls manually (we clear it in
    /// `updateScrollButton` when `distanceFromBottom > 150`).
    @State private var scrollPinAnchorID: String? = "bottom-anchor"
    @FocusState private var isInputFocused: Bool
    @State private var showConnectionStatus: Bool = true
    @State private var dragOffset: CGFloat = 0
    @State private var showSearch: Bool = false
    @State private var showRoomInfo: Bool = false
    @State private var selectedMessageForMenu: Message? = nil
    @State private var showThread: Bool = false
    @State private var selectedMessageForThread: Message? = nil
    @State private var showReportModal: Bool = false
    @State private var messageToReport: Message? = nil
    @State private var mediaPreview: MediaPreviewTarget? = nil
    @ObservedObject private var connectionManager: ConnectionManager
    
    private var chatBackgroundColor: Color {
        let effectiveConfig = viewModel.config ?? ConfigStore.shared.config
        if let hex = effectiveConfig.backgroundChat?.color, !hex.isEmpty {
            return Color(hex: hex)
        }
        #if os(iOS)
        return Color(uiColor: .systemGray6)
        #else
        return Color(NSColor.windowBackgroundColor)
        #endif
    }
    
    public init(viewModel: ChatRoomViewModel) {
        self.viewModel = viewModel
        self._connectionManager = ObservedObject(wrappedValue: ConnectionManager.shared)
    }
    
    // Helper function to build messages list
    @ViewBuilder
    private func buildMessagesList(proxy: ScrollViewProxy) -> some View {
        LazyVStack(spacing: 8) {
            // Error message banner at top (if there's an error)
            if let errorMessage = viewModel.loadError {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.primary)
                        Spacer()
                        Button(action: {
                            // Retry loading messages
                            viewModel.loadError = nil
                            viewModel.loadMessages(forceReload: true)
                        }) {
                            Text("Retry")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            
                            // Loader at top when loading more (matches TypeScript)
                            if viewModel.isLoadingMore {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Loading more messages...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .id("loader-top")
                            }
                            
                            // Filter messages - matches React Native MessageList.tsx logic exactly
                            // React Native: const nonDeletedMessages = addReplyMessages.filter((item: IMessage) => !item.deleted && !item.isDeleted);
                            // Then: item.showInChannel === "true" || ((!item.isReply || item.isReply === "false") && !item.mainMessage)
                            let filteredMessages = viewModel.messages.filter { msg in
                                // Match TypeScript: if (!message?.body) return;
                                guard !msg.body.isEmpty else {
                                    return false
                                }
                                
                                // Match TypeScript: if (message.deleted || message.isDeleted) return;
                                guard msg.isDeleted != true else {
                                    return false
                                }
                                
                                // Match React Native MessageList.tsx filter logic:
                                // item.showInChannel === "true" || ((!item.isReply || item.isReply === "false") && !item.mainMessage)
                                let showInChannel = msg.showInChannel == "true"
                                let isNotReply = msg.isReply != true && (msg.isReply == nil || msg.isReply == false)
                                let hasNoMainMessage = msg.mainMessage == nil || msg.mainMessage?.isEmpty == true
                                let shouldShow = showInChannel || (isNotReply && hasNoMainMessage)
                                
                                guard shouldShow else {
                                    return false
                                }
                                
                                // For pending messages, check if there's a confirmed version
                                if let pending = msg.pending, pending {
                                    // Check if there's a confirmed message with:
                                    // 1. Same content and user
                                    // 2. Or matching ID/xmppId
                                    let hasConfirmedVersion = viewModel.messages.contains { otherMsg in
                                        guard otherMsg.pending != true else { return false }
                                        
                                        // Match by ID/xmppId
                                        if otherMsg.id == msg.id ||
                                           (otherMsg.xmppId != nil && otherMsg.xmppId == msg.id) ||
                                           (msg.xmppId != nil && msg.xmppId == otherMsg.id) ||
                                           (otherMsg.xmppId != nil && msg.xmppId != nil && otherMsg.xmppId == msg.xmppId) {
                                            return true
                                        }
                                        
                                        // Match by content and user (fallback)
                                        if otherMsg.body == msg.body &&
                                           (otherMsg.user.id == msg.user.id || 
                                            otherMsg.user.xmppUsername == msg.user.xmppUsername) {
                                            return true
                                        }
                                        
                                        return false
                                    }
                                    // Only show pending if there's NO confirmed version
                                    return !hasConfirmedVersion
                                }
                                
                                // Keep all non-pending messages
                                return true
                            }
                            
                            ForEach(Array(filteredMessages.enumerated()), id: \.element.id) { index, message in
                                let previousMessage = index > 0 ? filteredMessages[index - 1] : nil
                                let nextMessage = index < filteredMessages.count - 1 ? filteredMessages[index + 1] : nil
                                
                                // Check if we need to show date separator
                                let showDateSeparator = shouldShowDateSeparator(
                                    currentMessage: message,
                                    previousMessage: previousMessage
                                )
                                
                                let nextMessageHasDateSeparator = nextMessage != nil ? shouldShowDateSeparator(
                                    currentMessage: nextMessage!,
                                    previousMessage: message
                                ) : false
                                
                                let showAvatar = nextMessage == nil || 
                                                 nextMessage?.user.id != message.user.id || 
                                                 nextMessageHasDateSeparator
                                
                                // Date separator
                                if showDateSeparator {
                                    DateSeparatorView(date: message.date)
                                        .padding(.vertical, 8)
                                }
                                
                                // Determine if message is from current user - break up complex expression
                                let isCurrentUserById = message.user.id == viewModel.currentUserId
                                let isCurrentUserByXmpp: Bool = {
                                    guard let currentUserXmpp = viewModel.currentUserXmppUsername,
                                          let messageUserXmpp = message.user.xmppUsername else {
                                    return false
                                    }
                                    let normalizedCurrent = currentUserXmpp.lowercased().trimmingCharacters(in: .whitespaces)
                                    let normalizedMessage = messageUserXmpp.lowercased().trimmingCharacters(in: .whitespaces)
                                    return normalizedCurrent == normalizedMessage
                                }()
                                let isUser = isCurrentUserById || isCurrentUserByXmpp
                                
                                MessageBubbleView(
                                message: message,
                                    isUser: isUser,
                                    showAvatar: showAvatar,
                                    previousMessage: previousMessage,
                                    onLongPress: {
                                        // Context menu will be shown via .contextMenu modifier
                                    },
                                    onRetry: isUser ? {
                                        viewModel.retryFailedMessage(message)
                                    } : nil,
                                    onReactionTap: { emoji in
                                        viewModel.addReaction(messageId: message.id, emoji: emoji)
                                    },
                                    onReply: {
                                        selectedMessageForThread = message
                                        showThread = true
                                    },
                                    onEdit: isUser ? {
                                        viewModel.isEditing = true
                                        viewModel.editText = message.body
                                        viewModel.editMessageId = message.id
                                        messageText = message.body
                                    } : nil,
                                    onDelete: isUser ? {
                                        viewModel.deleteMessage(message.id)
                                    } : nil,
                                    onReport: nil,
                                    onMediaTap: { mediaMessage in
                                        mediaPreview = MediaPreviewTarget(message: mediaMessage)
                                    },
                                    onDiscard: isUser ? {
                                        viewModel.discardFailedMessage(message.id)
                                    } : nil
//                                    onReport: !isUser ? {
//                                        messageToReport = message
//                                        showReportModal = true
//                                    } : nil
                            )
                            .id(message.id)
                            .onAppear {
                                // Track when message becomes visible for scroll button
                                // Use debounce to avoid excessive updates
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms debounce
                                    
                                    let totalMessages = filteredMessages.count
                                    // If we see one of the last 5 messages, we're at bottom
                                    let isNearBottom = index >= totalMessages - 5
                                    
                                    if isNearBottom {
                                        // At bottom - hide button
                                        showScrollButton = false
                                        isUserScrolledUp = false
                                        atBottom = true
                                        newMessagesCount = 0
                                    } else {
                                        // Scrolled up - show button
                                        showScrollButton = true
                                        isUserScrolledUp = true
                                        atBottom = false
                                    }
                                }
                            }
            }
        }
        .padding()
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Connection Status
            if showConnectionStatus {
                ConnectionStatusView(connectionManager: connectionManager)
            }
            
            // Header
            ChatHeaderView(
                room: viewModel.room,
                isTyping: viewModel.isTyping,
                composingUsers: viewModel.composingUsers,
                messages: viewModel.messages,
                currentUserId: viewModel.currentUserId,
                currentUserXmppUsername: viewModel.currentUserXmppUsername,
                onBack: {
                    presentationMode.wrappedValue.dismiss()
                },
                onInfo: {
                    showRoomInfo = true
                }
            )
            
            // Off-Clinic Hours Banner
            OffClinicHoursBanner()
            
            // Messages List
            ZStack {
                ScrollViewReader { proxy in
                    scrollViewAnchoredToBottom {
                        buildMessagesList(proxy: proxy)
                    }
                    .coordinateSpace(name: "messageScroll")
                    .sheet(isPresented: $showThread) {
                        if let message = selectedMessageForThread,
                           let currentUser = UserStore.shared.currentUser {
                            ThreadView(
                                activeMessage: message,
                                currentUser: currentUser,
                                onClose: {
                                    showThread = false
                                    selectedMessageForThread = nil
                                },
                                onSendMessage: { text, alsoSendToMain in
                                    viewModel.sendReply(messageId: message.id, text: text, alsoSendToMain: alsoSendToMain)
                                },
                                onSendMedia: { data, type in
                                    viewModel.sendMedia(data: data, type: type)
                                }
                            )
                        }
                    }
                    .sheet(isPresented: $showReportModal) {
                        if let message = messageToReport {
                            ReportModal(
                                type: .message,
                                onReport: { reason, additionalInfo in
                                    Task {
                                        do {
                                            // Extract chat name from room JID
                                            let chatName = viewModel.room.jid.components(separatedBy: "@").first ?? viewModel.room.jid
                                            let _ = try await RoomsAPI.postReportMessage(
                                                chatName: chatName,
                                                messageId: message.id,
                                                category: reason,
                                                text: additionalInfo.isEmpty ? nil : additionalInfo
                                            )
                                            //print("✅ Message reported successfully")
                                        } catch {
                                            //print("❌ Failed to report message: \(error.localizedDescription)")
                                        }
                                    }
                                },
                                onClose: {
                                    showReportModal = false
                                    messageToReport = nil
                                }
                            )
                        }
                    }
                    .sheet(isPresented: $showRoomInfo) {
                        RoomInfoModal(
                            room: viewModel.room,
                            members: viewModel.room.members ?? [],
                            onClose: { showRoomInfo = false },
                            onEdit: nil,
                            onLeave: nil,
                            onDelete: nil
                        )
                    }
                    .fullScreenCover(item: $mediaPreview) { target in
                        MediaPreviewHost(target: target, onClose: { mediaPreview = nil })
                    }
                    .background(
                        // Track scroll position and content dimensions
                        GeometryReader { outerGeometry in
                            Color.clear
                                .background(
                                    GeometryReader { innerGeometry in
                                        Color.clear
                                            .preference(
                                                key: ScrollMetricsKey.self,
                                                value: ScrollMetrics(
                                                    scrollTop: max(0, innerGeometry.frame(in: .named("messageScroll")).minY),
                                                    scrollHeight: innerGeometry.size.height,
                                                    clientHeight: outerGeometry.size.height
                                                )
                                            )
                                    }
                                )
                        }
                    )
                    .refreshable {
                        // Pull to refresh - load latest messages
                        // This also retries after errors
                        //print("🔄 Pull to refresh triggered from UI")
                        
                        // Clear any errors when user pulls to refresh
                        viewModel.loadError = nil
                        
                        // Call refreshMessages to load new messages
                        viewModel.refreshMessages()
                        
                        // Wait for refresh to complete (isRefreshing becomes false)
                        // This allows the refreshable spinner to show properly
                        var attempts = 0
                        let maxAttempts = 60 // 6 seconds (60 * 100ms) - longer timeout
                        
                        while attempts < maxAttempts && viewModel.isRefreshing {
                            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                            attempts += 1
                        }
                        
                        // Force clear isRefreshing if still set after timeout
                        if viewModel.isRefreshing {
                            viewModel.isRefreshing = false
                            //print("⏱️ Force clearing isRefreshing after timeout")
                        }
                        
                        if !viewModel.isRefreshing {
                            //print("✅ Pull-to-refresh complete: new messages loaded")
                        } else {
                            //print("⏱️ Timeout waiting for new messages after pull-to-refresh")
                        }
                    }
                    .onPreferenceChange(ScrollMetricsKey.self) { metrics in
                        // Debounced scroll handler (combines checkAtBottom and checkIfLoadMoreMessages)
                        handleScroll(metrics: metrics, proxy: proxy)
                    }
                    .onPreferenceChange(ContentHeightKey.self) { height in
                        contentHeight = height
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MessagesLoaded"))) { notification in
                        // Messages finished loading - scroll position restoration happens in viewModel
                        
                        // Read the actual message count from the notification
                        let userInfo = notification.userInfo ?? [:]
                        let oldCount = userInfo["oldCount"] as? Int ?? 0
                        let newCount = userInfo["newCount"] as? Int ?? viewModel.messages.count
                        let loadedCount = userInfo["loadedCount"] as? Int ?? (newCount - oldCount)
                        
                        //print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        //print("📜 SCROLL: Messages loaded notification received")
                        //print("   📊 Message count before load: \(oldCount)")
                        //print("   📊 Message count after load: \(newCount)")
                        //print("   📊 Messages loaded: \(loadedCount)")
                        //print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        
                        // Telegram-like: Restore scroll position after loading older messages
                        if let scrollInfo = viewModel.getScrollPositionInfo() {
                            // Only restore if we actually loaded new messages (count increased)
                            if newCount > oldCount {
                                // Find the message that was at the top before loading
                                // After loading, it should be at the same visual position
                                if let messageIndex = viewModel.messages.firstIndex(where: { $0.id == scrollInfo.messageId }) {
                                    //print("📌 Restoring scroll position: messageId=\(scrollInfo.messageId), oldIndex=\(scrollInfo.messageIndex), newIndex=\(messageIndex), oldCount=\(oldCount), newCount=\(newCount)")
                                    
                                    // Small delay to ensure messages are rendered
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        // Scroll to the same message, maintaining visual position
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            proxy.scrollTo(scrollInfo.messageId, anchor: .top)
                                        }
                                        viewModel.clearScrollPositionInfo()
                                    }
                                } else {
                                    // Message not found, clear the saved position
                                    viewModel.clearScrollPositionInfo()
                                }
                            } else {
                                viewModel.clearScrollPositionInfo()
                            }
                        }
                    }
                    .onChange(of: viewModel.messages.count) { newCount in
                        guard newCount > 0 else { return }
                        
                        // Track new messages count (matches TypeScript logic)
                        if newCount > lastMessageCount {
                            let lastMessage = viewModel.messages.last
                            let isLastMessageFromUser = lastMessage != nil && {
                                if lastMessage!.user.id == viewModel.currentUserId {
                                    return true
                                }
                                if let currentUserXmpp = viewModel.currentUserXmppUsername,
                                   let messageUserXmpp = lastMessage!.user.xmppUsername {
                                    return currentUserXmpp.lowercased().trimmingCharacters(in: .whitespaces) == 
                                           messageUserXmpp.lowercased().trimmingCharacters(in: .whitespaces)
                                }
                                return false
                            }()
                            
                            // If not from user and user is scrolled up, increment counter
                            if !isLastMessageFromUser && isUserScrolledUp {
                                newMessagesCount += 1
                            }
                            
                            // If last message is from user, auto-scroll
                            if isLastMessageFromUser {
                                scrollToBottom(proxy: proxy)
                            }
                        }
                        
                        lastMessageCount = newCount
                        
                        // Don't auto-scroll if we're loading more (maintaining position)
                        // Or if this is pull-to-refresh (don't auto-scroll)
                        if viewModel.isLoadingMore {
                            return
                        }
                        
                        // Only scroll on initial load or when restoring position
                        // Don't scroll on every message count change to avoid lag
                        // After pull-to-refresh don't auto-scroll — preserve the position
                        if pinToBottom, viewModel.messages.last != nil {
                            // Keep pinning bottom until the user scrolls
                            // manually. Same multi-hop loop as in `onAppear`
                            // — a single `scrollTo` can land slightly above
                            // the true bottom because LazyVStack lays rows
                            // out on demand. Repeating for ~300ms catches
                            // settlement. Stops immediately if the user
                            // flips `pinToBottom` off by scrolling up.
                            Task { @MainActor in
                                for _ in 0..<6 {
                                    if !pinToBottom { return }
                                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                                    try? await Task.sleep(nanoseconds: 50_000_000)
                                }
                                hasPerformedInitialScroll = true
                            }
                        } else if let savedPosition = viewModel.getScrollPosition(),
                                  viewModel.messages.contains(where: { $0.id == savedPosition }),
                                  !viewModel.hasRestoredScrollPosition {
                            // Restore saved scroll position only once
                            viewModel.markScrollPositionRestored()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    proxy.scrollTo(savedPosition, anchor: .center)
                                }
                            }
                        }
                    }
                    .onChange(of: viewModel.isLoading) { isLoading in
                        // When loading finishes, re-pin to the bottom while
                        // `pinToBottom` is still armed. This catches the
                        // case where the chat opened on an empty state and
                        // the first cache/MAM batch arrived after `onAppear`.
                        if !isLoading && pinToBottom, viewModel.messages.last != nil {
                            Task { @MainActor in
                                for _ in 0..<6 {
                                    if !pinToBottom { return }
                                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                                    try? await Task.sleep(nanoseconds: 50_000_000)
                                }
                                hasPerformedInitialScroll = true
                            }
                        }
                    }
                    .onChange(of: viewModel.composingUsers) { composingList in
                        // Auto-scroll when typing starts if user is at bottom (matches TypeScript)
                        if !isUserScrolledUp && !composingList.isEmpty {
                    if let lastMessage = viewModel.messages.last {
                                scrollToBottom(proxy: proxy)
                            }
                        }
                    }
                    .onAppear {
                        // Store proxy for button access
                        scrollProxy = proxy

                        // Re-arm bottom-pin on every open: we want the chat
                        // to always land at the newest message, including
                        // repeat opens and cases where `messages` arrive a
                        // second or two after `onAppear`. The pin is
                        // dropped the moment the user manually scrolls up.
                        pinToBottom = true
                        hasPerformedInitialScroll = false
                        isUserScrolledUp = false
                        // iOS 17+ scroll-position binding: re-pointing at
                        // `bottom-anchor` tells SwiftUI to anchor the
                        // ScrollView's visual bottom to this id and keep
                        // it stable through content / viewport changes
                        // (new messages arriving, keyboard appearing).
                        scrollPinAnchorID = "bottom-anchor"

                        // `LazyVStack` inside `ScrollView` lays out rows
                        // incrementally, so a single `scrollTo(bottom)` at
                        // `onAppear` can land slightly above the true
                        // bottom (last row's intrinsic height is computed
                        // only after it's rendered). We pin for a short
                        // window: repeated scrollTo calls every 50ms for
                        // ~1s — this soaks up LazyVStack settlement and
                        // any MAM/cache batch that lands shortly after
                        // `onAppear`. Stops as soon as the user scrolls
                        // up manually (which flips `pinToBottom` off).
                        Task { @MainActor in
                            for _ in 0..<20 {
                                if !pinToBottom { return }
                                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                                try? await Task.sleep(nanoseconds: 50_000_000)
                            }
                            hasPerformedInitialScroll = true
                        }
                    }
                }
                
                // Loader overlay (matches TypeScript - shows at top of scroll view)
                if viewModel.isLoading {
                    VStack {
                        ProgressView()
                            .scaleEffect(1.5)
                            .padding()
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(Color.clear)
                }
                
            }
            
            // Input Area
            ConfigurableChatInputView(
                messageText: $messageText,
                onSendMessage: { text in
                    viewModel.stopTyping() // Stop typing when sending
                    if viewModel.isEditing, let messageId = viewModel.editMessageId {
                        viewModel.editMessage(messageId, newText: text)
                        viewModel.cancelEdit()
                    messageText = ""
                    } else {
                        viewModel.sendMessage(text)
                        messageText = ""
                    }
                },
                onSendMedia: { data, type, caption in
                    viewModel.stopTyping() // Stop typing when sending media
                    viewModel.sendMedia(data: data, type: type, caption: caption)
                },
                isEditing: viewModel.isEditing,
                editMessageId: viewModel.editMessageId,
                onCancelEdit: {
                    viewModel.stopTyping() // Stop typing when canceling edit
                    viewModel.cancelEdit()
                    messageText = ""
                },
                customComponent: viewModel.config?.customComponents?.customInputComponent
            )
            .focused($isInputFocused)
            .onChange(of: messageText) { _ in
                // Start typing when user types (debounced in startTyping)
                if !messageText.isEmpty {
                    viewModel.startTyping()
                } else {
                    viewModel.stopTyping()
                }
            }
            .onChange(of: isInputFocused) { focused in
                // Stop typing when input loses focus
                if !focused {
                    viewModel.stopTyping()
                }
            }
        }
        // Web-like background
        .background(
            chatBackgroundColor.ignoresSafeArea()
        )
        #if os(iOS)
        .modifier(HideNavigationBarModifier())
        #endif
        .onAppear {
            viewModel.onViewAppeared()
            // Reset scroll button state when room appears (matches React Native useEffect)
            showScrollButton = false
            isUserScrolledUp = false
            atBottom = true
            newMessagesCount = 0
        }
        .onDisappear {
            // Save scroll position when leaving the chat
            // Use the last message as a fallback if we don't have a tracked visible message
            viewModel.saveScrollPosition(messageId: nil)

            // Release the "active room" pointer immediately so that any
            // message arriving after the user swipes back starts bumping the
            // unread badge again. `deinit` of the view model eventually does
            // the same, but SwiftUI sometimes keeps the ViewModel around
            // briefly for @StateObject reuse, which would otherwise suppress
            // the next incoming-message badge.
            if RoomStore.shared.activeRoomJID == viewModel.room.jid {
                RoomStore.shared.activeRoomJID = nil
            }
            // Stamp the moment we left as the new "last viewed" so anything
            // that arrives after this moment counts as unread (matches how
            // Telegram resets its unread baseline on leaving a chat).
            RoomStore.shared.setLastViewedTimestamp(
                roomJID: viewModel.room.jid,
                timestamp: Int64(Date().timeIntervalSince1970 * 1000)
            )
            // Force a recompute so the badge in the room list immediately
            // reflects the correct count (0 right after close; new messages
            // that land later will bump it).
            let myLocal = UserStore.shared.currentUser?.xmppUsername?
                .components(separatedBy: "@").first ?? ""
            RoomStore.shared.recomputeUnreadForRoom(
                jid: viewModel.room.jid,
                currentUserLocal: myLocal
            )
        }
        .onChange(of: viewModel.room.jid) { _ in
            // Reset scroll button state when room changes (matches React Native useEffect)
            showScrollButton = false
            isUserScrolledUp = false
            atBottom = true
            newMessagesCount = 0
        }
        .overlay(
            // Scroll to Bottom Button - OVERLAY on top of everything
            // React Native: position: absolute, bottom: 20, right: 20, width: 40, height: 40
            // TEMPORARY: Always show for testing
            Group {
                if showScrollButton {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: {
                                if let proxy = scrollProxy {
                                    scrollToBottom(proxy: proxy)
                                    // Hide button immediately when clicked (matches React Native)
                                    showScrollButton = false
                                    isUserScrolledUp = false
                                    atBottom = true
                                    newMessagesCount = 0
                                }
                            }) {
                                ZStack {
                                    // Match React Native: backgroundColor: config?.colors?.secondary || "#007AFF"
                                    Circle()
                                        .fill(viewModel.config?.colors?.secondaryColor ?? Color(hex: "#007AFF"))
                                        .frame(width: 40, height: 40)
                                        .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 2)
                                    
                                    // Match React Native: ArowDownIcon
                                    Image(systemName: "arrow.down")
                                        .foregroundColor(.white)
                                        .font(.system(size: 16, weight: .semibold))
                                    
                                    // Optional: Show new messages count badge (if needed)
                                    if newMessagesCount > 0 {
                                        Text("\(newMessagesCount)")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(4)
                                            .background(Color.red)
                                            .clipShape(Circle())
                                            .offset(x: 14, y: -14)
                                    }
                                }
                            }
                            .padding(.trailing, 20)
                            .padding(.bottom, 80)
                        }
                    }
                    .allowsHitTesting(true)
                }
            },
            alignment: .bottomTrailing
        )
    }
    
    // MARK: - Helper Functions
    
    /// Anchors the `ScrollView` to the bottom on first layout (iOS 17+),
    /// so the chat opens showing the newest message — no perceived "scroll
    /// from top" animation. On iOS < 17 the view simply starts at the top;
    /// our `.onAppear` fallback then jumps to the last message without
    /// animation to approximate the same UX.
    ///
    /// Also dismisses the keyboard as soon as the user starts scrolling
    /// (iOS 16+), and on any tap that lands on the scroll view's empty
    /// area — matches Telegram/Messages behaviour.
    @ViewBuilder
    private func scrollViewAnchoredToBottom<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let baseScroll = ScrollView { content() }
            .simultaneousGesture(
                // Use `simultaneousGesture` so taps on message bubbles still
                // fire their own handlers — this just adds an extra observer
                // for the tap and uses it to drop the keyboard.
                TapGesture().onEnded { dismissKeyboard() }
            )

        if #available(iOS 17.0, macOS 14.0, *) {
            baseScroll
                .defaultScrollAnchor(.bottom)
                .scrollPosition(id: $scrollPinAnchorID, anchor: .bottom)
                .scrollDismissesKeyboard(.immediately)
        } else if #available(iOS 16.0, macOS 13.0, *) {
            baseScroll
                .scrollDismissesKeyboard(.immediately)
        } else {
            baseScroll
        }
    }

    private func dismissKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        #endif
    }

    /// Sentinel ID that sits at the very end of the messages LazyVStack
    /// (`Color.clear.frame(height: 1).id("bottom-anchor")`). Scrolling to
    /// this anchor lands past the bubble+padding of the last message, so the
    /// last bubble is always fully visible — unlike scrolling to
    /// `lastMessage.id` with anchor `.bottom`, which only aligns the bubble
    /// body and can leave its bottom padding clipped by the input bar.
    private static let bottomAnchorID = "bottom-anchor"

    /// Scroll to bottom function (matches TypeScript scrollToBottom)
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if viewModel.messages.last != nil {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
            showScrollButton = false
            newMessagesCount = 0
        }
    }
    
    /// Check if at bottom and handle scroll button (matches React Native MessageList.tsx exactly)
    /// React Native: if (contentOffset < 150) { setIsUserAtBottom(true); setShowNewMessageIndicator(false); }
    ///                else { setIsUserAtBottom(false); if (hasUserScrolled) { setShowNewMessageIndicator(true); } }
    private func checkAtBottom(metrics: ScrollMetrics, proxy: ScrollViewProxy) {
        // In SwiftUI ScrollView:
        // - scrollTop: position from top (0 when at top, increases when scrolling down)
        // - scrollHeight: total content height
        // - clientHeight: visible viewport height
        // - distanceFromBottom = scrollHeight - clientHeight - scrollTop
        
        // TEMPORARY DEBUG: Always log to see what's happening
        let distanceFromBottom = metrics.scrollHeight - metrics.clientHeight - metrics.scrollTop

        // Guard: If content doesn't need scrolling, hide button
        guard metrics.scrollHeight > metrics.clientHeight else {
            showScrollButton = false
            isUserScrolledUp = false
            atBottom = true
            return
        }
        
        // Match React Native: if (contentOffset < 150) - user is at bottom
        // In our case: if distanceFromBottom <= 150, user is at bottom (hide button)
        // If distanceFromBottom > 150, user scrolled up (show button)
        if distanceFromBottom <= 150 {
            // User is at bottom - hide button
            print("   → At bottom (distance=\(Int(distanceFromBottom))), HIDING button")
            showScrollButton = false
            isUserScrolledUp = false
            atBottom = true
            newMessagesCount = 0
        } else {
            // User scrolled up - show button
            showScrollButton = true
            isUserScrolledUp = true
            atBottom = false
            // User took scroll control — stop auto-pinning to the bottom.
            // Re-armed on next `onAppear`.
            pinToBottom = false
            // Release the iOS 17 scroll-position binding so SwiftUI doesn't
            // keep yanking the view back to the bottom while the user is
            // reading history. Re-pointed at `bottom-anchor` in onAppear.
            if scrollPinAnchorID != nil {
                scrollPinAnchorID = nil
            }
        }
    }
    
    /// Single trigger point for loading more messages (matches web version)
    /// TypeScript: if (params.top >= 150 || isLoadingMore.current) return;
    private func checkIfLoadMoreMessages(metrics: ScrollMetrics) {
        // Guard: Don't load if already loading or history complete
        guard !viewModel.isLoadingMore else { return }
        guard viewModel.room.historyComplete != true else { return }

        // Guard: wait until the chat has performed its initial pin-to-bottom.
        // Before that, SwiftUI reports `scrollTop == 0` at layout time, which
        // would incorrectly trigger a "load more older messages" request the
        // moment the user opens a room.
        guard hasPerformedInitialScroll else { return }

        // Guard: Only trigger when near top (scrollTop < 150px) - matches TypeScript
        guard metrics.scrollTop < 150 else { return }
        
        // Get first message (skip delimiter-new) - matches web version exactly
        let firstMessage = viewModel.messages.first(where: { $0.id != "delimiter-new" }) 
                         ?? viewModel.messages.first
        
        guard let message = firstMessage else { 
            //print("⚠️ checkIfLoadMoreMessages: No first message found")
            return 
        }
        
        // Match web version: Number(firstMessageId) - try to convert message.id to number
        // This matches TypeScript: loadMoreMessages(firstMessage.roomJid, 30, Number(firstMessageId))
        let beforeTimestamp: Int64? = {
            // First, try to convert message.id directly to Int64 (like Number() in TypeScript)
            if let numericId = Int64(message.id) {
                //print("📜 Using message.id as numeric: \(numericId)")
                return numericId
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
        
        guard let before = beforeTimestamp else {
            //print("❌ checkIfLoadMoreMessages: Could not determine beforeTimestamp for message.id=\(message.id)")
            return
        }
        
        //print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        //print("📜 Triggering loadMoreMessages:")
        //print("   scrollTop: \(Int(metrics.scrollTop))")
        //print("   firstMessage.id: \(message.id)")
        //print("   firstMessage.timestamp: \(message.timestamp?.description ?? "nil")")
        //print("   beforeTimestamp (to send): \(before)")
        //print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        // Save scroll position before loading
        if let firstMsg = viewModel.messages.first {
            viewModel.saveScrollPositionBeforeLoad()
        }
        
        // Load more messages - matches web: loadMoreMessages(roomJid, 30, Number(firstMessageId))
        viewModel.loadMoreMessages(max: 30, beforeTimestamp: before)
    }
    
    /// Debounced scroll handler - combines checkAtBottom and checkIfLoadMoreMessages
    private func handleScroll(metrics: ScrollMetrics, proxy: ScrollViewProxy) {
        // Update state immediately (no debounce for button visibility)
        // Check if at bottom (for scroll button visibility)
        checkAtBottom(metrics: metrics, proxy: proxy)
        
        // Debounce only for loading more messages
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms debounce
            
            // Check if should load more (single trigger point)
            checkIfLoadMoreMessages(metrics: metrics)
        }
    }

}

#if os(iOS)
/// Hides the navigation bar on iOS using the modern toolbar API (iOS 16+)
/// when available, falling back to `.navigationBarHidden` on iOS 15. The
/// legacy `.navigationBarHidden(true)` is known to leak into the parent
/// view on pop, breaking `RoomListView`'s title/search/toolbar on return.
private struct HideNavigationBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.toolbar(.hidden, for: .navigationBar)
        } else {
            content.navigationBarHidden(true)
        }
    }
}
#endif
