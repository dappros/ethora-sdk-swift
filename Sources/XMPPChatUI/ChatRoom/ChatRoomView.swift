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
    @FocusState private var isInputFocused: Bool
    @State private var showConnectionStatus: Bool = true
    @State private var showSearch: Bool = false
    @State private var showRoomInfo: Bool = false
    @State private var selectedMessageForMenu: Message? = nil
    @State private var showThread: Bool = false
    @State private var selectedMessageForThread: Message? = nil
    @State private var showReportModal: Bool = false
    @State private var messageToReport: Message? = nil
    @ObservedObject private var connectionManager: ConnectionManager
    
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
                            
                            ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                                let previousMessage = index > 0 ? viewModel.messages[index - 1] : nil
                                let nextMessage = index < viewModel.messages.count - 1 ? viewModel.messages[index + 1] : nil
                                
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
                                    onRetry: nil,
                                    // onRetry: {
                                    //     // Retry sending failed message
                                    //     if message.pending == false && message.xmppId == nil {
                                    //         viewModel.resendMessage(message)
                                    //     }
                                    // },
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
                                    onReport: nil
//                                    onReport: !isUser ? {
//                                        messageToReport = message
//                                        showReportModal = true
//                                    } : nil
                            )
                            .id(message.id)
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
                    ScrollView {
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
                            members: [], // TODO: Load room members
                            onClose: { showRoomInfo = false },
                            onEdit: nil,
                            onLeave: nil,
                            onDelete: nil
                        )
                    }
                    .background(
                        // Track scroll position and dimensions (matches TypeScript checkAtBottom)
                        GeometryReader { scrollGeometry in
                            Color.clear
                                .preference(
                                    key: ScrollMetricsKey.self,
                                    value: ScrollMetrics(
                                        scrollTop: max(0, -scrollGeometry.frame(in: .named("messageScroll")).minY),
                                        scrollHeight: scrollGeometry.size.height,
                                        clientHeight: scrollGeometry.size.height
                                    )
                                )
                        }
                    )
                    .background(
                        // Track total content height using LazyVStack
                        GeometryReader { contentGeometry in
                            Color.clear
                                .preference(
                                    key: ContentHeightKey.self,
                                    value: contentGeometry.size.height
                                )
                        }
                    )
                    .refreshable {
                        // Pull to refresh - load latest messages
                        // This also retries after errors
                        //print("🔄 Pull to refresh triggered from UI")
                        
                        // Clear any errors when user pulls to refresh
                        viewModel.loadError = nil
                        
                        // Викликаємо refreshMessages для завантаження нових повідомлень
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
                            //print("✅ Pull-to-refresh завершено: нові повідомлення завантажено")
                        } else {
                            //print("⏱️ Timeout очікування нових повідомлень після pull-to-refresh")
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
                        
                        // Отримуємо фактичну кількість повідомлень з notification
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
                        // Або якщо це pull-to-refresh (не скролимо автоматично)
                        if viewModel.isLoadingMore {
                            return
                        }
                        
                        // Only scroll on initial load or when restoring position
                        // Don't scroll on every message count change to avoid lag
                        // Після pull-to-refresh не скролимо автоматично - зберігаємо позицію
                        if viewModel.shouldScrollToBottom(), let lastMessage = viewModel.messages.last {
                            // Small delay to ensure messages are rendered
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
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
                        // When loading completes, scroll to bottom if it was the first load
                        if !isLoading && viewModel.shouldScrollToBottom(), let lastMessage = viewModel.messages.last {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
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
                        
                        // When view appears, restore scroll position if available
                        if let savedPosition = viewModel.getScrollPosition(),
                           viewModel.messages.contains(where: { $0.id == savedPosition }),
                           !viewModel.hasRestoredScrollPosition {
                            viewModel.markScrollPositionRestored()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    proxy.scrollTo(savedPosition, anchor: .center)
                                }
                            }
                        } else if viewModel.shouldScrollToBottom(), let lastMessage = viewModel.messages.last {
                            // First load - scroll to bottom
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
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
                
                // Scroll to Bottom Button (matches TypeScript ScrollToBottomButton)
                if showScrollButton {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: {
                                if let proxy = scrollProxy {
                                    scrollToBottom(proxy: proxy)
                                }
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 40, height: 40)
                                        .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 2)
                                    
                                    Image(systemName: "arrow.down")
                                        .foregroundColor(.white)
                                        .font(.system(size: 16, weight: .semibold))
                                    
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
                            .padding(.bottom, 20)
                        }
                    }
                }
            }
            
            // Typing Indicator
            if viewModel.isTyping {
                TypingIndicatorView(users: viewModel.composingUsers)
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
                onSendMedia: { data, type in
                    viewModel.stopTyping() // Stop typing when sending media
                    viewModel.sendMedia(data: data, type: type)
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
            Color(red: 0.98, green: 0.98, blue: 0.99)
            .ignoresSafeArea()
        )
        #if os(iOS)
        .navigationBarHidden(true)
        #endif
        .onAppear {
            viewModel.onViewAppeared()
        }
        .onDisappear {
            // Save scroll position when leaving the chat
            // Use the last message as a fallback if we don't have a tracked visible message
            viewModel.saveScrollPosition(messageId: nil)
        }
    }
    
    // MARK: - Helper Functions
    
    /// Scroll to bottom function (matches TypeScript scrollToBottom)
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastMessage = viewModel.messages.last {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
            showScrollButton = false
            newMessagesCount = 0
        }
    }
    
    /// Check if at bottom and handle scroll button (matches TypeScript checkAtBottom)
    private func checkAtBottom(metrics: ScrollMetrics, proxy: ScrollViewProxy) {
            // Calculate distance from bottom (matches TypeScript exactly)
            let distanceFromBottom = metrics.scrollHeight - metrics.clientHeight - metrics.scrollTop
            
            let isNearBottom = distanceFromBottom <= 150
            let isAtBottom = distanceFromBottom <= 5
            
            atBottom = isAtBottom
            isUserScrolledUp = !isNearBottom
            
            let scrolledUp = distanceFromBottom > 150
            
        // Match web version logic exactly:
        // - Show button when scrolled up (> 150px from bottom)
        // - Hide button and scroll when at bottom (<= 5px from bottom)
        // - Hide button when near bottom (between 5px and 150px)
            if scrolledUp {
                showScrollButton = true
            } else if isAtBottom {
                scrollToBottom(proxy: proxy)
            showScrollButton = false
            newMessagesCount = 0
        } else if isNearBottom {
            // Near bottom but not exactly at bottom: hide button
            showScrollButton = false
        }
    }
    
    /// Single trigger point for loading more messages (matches web version)
    /// TypeScript: if (params.top >= 150 || isLoadingMore.current) return;
    private func checkIfLoadMoreMessages(metrics: ScrollMetrics) {
        // Guard: Don't load if already loading or history complete
        guard !viewModel.isLoadingMore else { return }
        guard viewModel.room.historyComplete != true else { return }
        
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
        // Debounce to prevent excessive calls (100ms - better performance than 50ms)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms debounce
            
            // Check if at bottom (for scroll button visibility)
            checkAtBottom(metrics: metrics, proxy: proxy)
            
            // Check if should load more (single trigger point)
            checkIfLoadMoreMessages(metrics: metrics)
        }
    }
    
}

// MARK: - Chat Header
struct ChatHeaderView: View {
    let room: Room
    let onBack: () -> Void
    let onInfo: (() -> Void)?
    
    init(
        room: Room,
        onBack: @escaping () -> Void,
        onInfo: (() -> Void)? = nil
    ) {
        self.room = room
        self.onBack = onBack
        self.onInfo = onInfo
    }
    
    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.blue)
            }
            .padding(.trailing, 8)
            
            if let icon = room.icon, let url = URL(string: icon) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(room.title)
                    .font(.headline)
                Text("\(room.usersCnt) members")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if let onInfo = onInfo {
                Button(action: onInfo) {
                    Image(systemName: "info.circle")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        #if os(iOS)
        .background(Color(uiColor: .systemBackground))
        #else
        .background(Color(NSColor.controlBackgroundColor))
        #endif
        .shadow(radius: 1)
    }
}

// MARK: - Message Bubble
struct MessageBubbleView: View {
    let message: Message
    let isUser: Bool
    let showAvatar: Bool
    let previousMessage: Message?
    let onLongPress: (() -> Void)?
    let onRetry: (() -> Void)?
    let onReactionTap: ((String) -> Void)?
    let onReply: (() -> Void)?
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?
    let onReport: (() -> Void)?
    
    @State private var showContextMenu = false
    @State private var showReactionPicker = false
    
    var body: some View {
        // Check if this is a delimiter message
        if message.id == "delimiter-new" {
            return AnyView(
                UnreadMessagesDelimiter()
            )
        }
        
        // Check if previous message is from same user
        let isConsecutive = previousMessage?.user.id == message.user.id
        
        // Build avatar view separately to reduce complexity
        @ViewBuilder
        func buildAvatarView() -> some View {
            if !isUser {
                if showAvatar {
                    SizedAvatarView(user: message.user, size: 32)
                } else {
                    Color.clear.frame(width: 32, height: 32)
                }
            } else {
                Color.clear.frame(width: 0, height: 0)
            }
        }
            
        // Build message content separately
        @ViewBuilder
        func buildMessageContent() -> some View {
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                        // Show username only for others and if not consecutive
                        if !isUser && (!isConsecutive || !showAvatar) {
                    Text(message.user.fullName)
                        .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(isUser ? .white.opacity(0.8) : .black)
                }
                
                // Check if this is a media message and determine MIME type
                buildMediaOrTextContent()
                
                // Reactions
                if let reactions = message.reaction, !reactions.isEmpty {
                    ReactionBadgesView(reactions: reactions)
                        .padding(.top, 4)
                }
                
                // Time and status
                HStack(spacing: 4) {
                    if !isUser {
                        Spacer()
                    }
                    Text(message.date, style: .time)
                        .font(.caption2)
                        .foregroundColor(isUser ? .white.opacity(0.7) : .gray)
                    
                    if isUser {
                        MessageStatusIndicatorView(message: message, onRetry: onRetry)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isUser ? Color.blue : Color.white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
            .overlay(
                Group {
                    if showReactionPicker {
                        ReactionPickerView(
                            onReactionSelected: { emoji in
                                onReactionTap?(emoji)
                                showReactionPicker = false
                            },
                            onDismiss: {
                                showReactionPicker = false
                            }
                        )
                        .offset(y: -60)
                    }
                },
                alignment: .top
            )
        }
        
        // Build media or text content
        @ViewBuilder
        func buildMediaOrTextContent() -> some View {
                    let hasMediaFlag = message.isMediafile == "true"
                    let hasMediaBody = message.body.lowercased() == "media"
                    let hasLocation = message.location != nil && !message.location!.isEmpty
                    let isMediaMessage = hasMediaFlag || (hasMediaBody && hasLocation) || hasLocation
                    
                    if isMediaMessage {
                        let mimeType: String = {
                            if let existingMimeType = message.mimetype, !existingMimeType.isEmpty {
                                return existingMimeType
                            } else if let location = message.location {
                                return inferMimeType(from: location)
                            } else {
                                return "application/octet-stream"
                            }
                        }()
                        
                        MediaMessagePreview(
                            message: message,
                            mimeType: mimeType,
                            isUser: isUser
                        )
                    } else {
                        if message.body.lowercased() != "media" {
                    UniversalMarkdownTextView(
                        text: message.body,
                        foregroundColor: isUser ? .white : .black
                    )
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
                        
        return AnyView(
            HStack(alignment: .bottom, spacing: 4) {
                if isUser {
                    Spacer()
                }
                
                buildAvatarView()
                
                Group {
                    if isUser {
                        VStack(alignment: .trailing, spacing: 2) {
                            buildMessageContent()
                                .contextMenu {
                                    MessageContextMenuItems(
                                        message: message,
                                        isUser: isUser,
                                        onReply: onReply,
                                        onCopy: {
                                            #if os(iOS)
                                            UIPasteboard.general.string = message.body
                                            #else
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(message.body, forType: .string)
                                            #endif
                                        },
                                        onEdit: onEdit,
                                        onDelete: onDelete,
                                        onReport: onReport
                                    )
                                }
                                .onLongPressGesture {
                                    onLongPress?()
                                    if onReactionTap != nil {
                                        showReactionPicker = true
                                    }
                                    HapticFeedback.buttonPress()
                                }
                        }
                        .frame(maxWidth: {
                            #if os(iOS)
                            return UIScreen.main.bounds.width * 0.75
                            #else
                            return 300
                            #endif
                        }(), alignment: .trailing)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            buildMessageContent()
                                .contextMenu {
                                    MessageContextMenuItems(
                                        message: message,
                                        isUser: isUser,
                                        onReply: onReply,
                                        onCopy: {
                                            #if os(iOS)
                                            UIPasteboard.general.string = message.body
                                            #else
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(message.body, forType: .string)
                                            #endif
                                        },
                                        onEdit: onEdit,
                                        onDelete: onDelete,
                                        onReport: onReport
                                    )
                                }
                                .onLongPressGesture {
                                    onLongPress?()
                                    if onReactionTap != nil {
                                        showReactionPicker = true
                                    }
                                    HapticFeedback.buttonPress()
                                }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
                
                if !isUser {
                    Spacer()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
        )
    }
}

// MARK: - Message Status Indicator
struct MessageStatusIndicatorView: View {
    let message: Message
    let onRetry: (() -> Void)?
    
    var body: some View {
        Group {
            if let pending = message.pending, pending {
                // Message is pending/sending
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
            } else if message.xmppId == nil && message.pending == false {
                // Message failed to send
                Button(action: {
                    onRetry?()
                }) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            } else {
                // Message sent successfully
                Image(systemName: "checkmark")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
}

// MARK: - Message Context Menu Items
struct MessageContextMenuItems: View {
    let message: Message
    let isUser: Bool
    let onReply: (() -> Void)?
    let onCopy: (() -> Void)?
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?
    let onReport: (() -> Void)?
    
    var body: some View {
        Group {
            // if let onReply = onReply {
            //     Button(action: onReply) {
            //         Label("Reply", systemImage: "arrowshape.turn.up.left")
            //     }
            // }
            
            if let onCopy = onCopy {
                Button(action: onCopy) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
            
            if isUser, let onEdit = onEdit {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
            }
            
            if isUser, let onDelete = onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
            
//            if !isUser, let onReport = onReport {
//                Button(role: .destructive, action: onReport) {
//                    Label("Report", systemImage: "exclamationmark.triangle")
//                }
//            }
        }
    }
}

// MARK: - Avatar View with Photo or Initials
struct SizedAvatarView: View {
    let user: User
    let size: CGFloat
    
    var initials: String {
        let firstName = user.firstName ?? ""
        let lastName = user.lastName ?? ""
        let firstInitial = firstName.first.map(String.init) ?? ""
        let lastInitial = lastName.first.map(String.init) ?? ""
        return (firstInitial + lastInitial).uppercased()
    }
    
    var body: some View {
        if let photoURL = user.profileImage, !photoURL.isEmpty, let url = URL(string: photoURL) {
            // Show photo if available
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                    .clipShape(Circle())
                case .failure(let error):
                    // Only log non-cancellation errors (cancellation is normal when views update)
                    let _ = {
                        if let urlError = error as? URLError, urlError.code != .cancelled {
                            // Log actual errors (network failures, invalid URLs, etc.)
                            //print("⚠️ Error loading avatar (non-cancellation): \(error.localizedDescription)")
                        }
                    }()
                    // Fallback to initials if image fails to load
                    InitialsAvatar(initials: initials, size: size)
                case .empty:
                    // Show placeholder while loading, or initials
                    InitialsAvatar(initials: initials, size: size)
                @unknown default:
                    InitialsAvatar(initials: initials, size: size)
                }
            }
        } else {
            // Show initials if no photo
            InitialsAvatar(initials: initials, size: size)
        }
    }
}

// MARK: - Initials Avatar
struct InitialsAvatar: View {
    let initials: String
    let size: CGFloat
    
    var body: some View {
        ZStack {
                        Circle()
                .fill(LinearGradient(
                    colors: [Color.blue.opacity(0.7), Color.purple.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            
            Text(initials)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Unread Messages Delimiter
struct UnreadMessagesDelimiter: View {
    var body: some View {
        HStack {
            Rectangle()
                .fill(Color.red)
                .frame(height: 1)
            
            Text("New Messages")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.red)
                .padding(.horizontal, 8)
            
            Rectangle()
                .fill(Color.red)
                .frame(height: 1)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Typing Indicator with Animation
struct TypingIndicatorView: View {
    let users: [String]
    @State private var animatingDots: Int = 0
    
    var body: some View {
        HStack(spacing: 4) {
            Text(typingText)
                .font(.caption)
                .foregroundColor(.black)
                .padding(.leading)
            
            // Animated dots
            HStack(spacing: 2) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.black)
                        .frame(width: 4, height: 4)
                        .opacity(animatingDots == index ? 1.0 : 0.3)
                        .animation(
                            Animation.easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.2),
                            value: animatingDots
                        )
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.8))
        .cornerRadius(8)
        .padding(.horizontal)
        .onAppear {
            // Start animation
            withAnimation {
                animatingDots = 0
            }
            // Cycle through dots
            Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
                withAnimation {
                    animatingDots = (animatingDots + 1) % 3
                }
            }
        }
    }
    
    private var typingText: String {
        if users.isEmpty {
            return "Someone is typing"
        } else if users.count == 1 {
            return "\(users[0]) is typing"
        } else if users.count == 2 {
            return "\(users[0]) and \(users[1]) are typing"
        } else {
            return "\(users.count) people are typing"
        }
    }
}

// MARK: - Date Separator
struct DateSeparatorView: View {
    let date: Date
    
    var body: some View {
        HStack {
            line
            Text(formattedDate)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.gray.opacity(0.15))
                )
            line
        }
        .padding(.horizontal)
    }
    
    private var line: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(height: 1)
    }
    
    private var formattedDate: String {
        let calendar = Calendar.current
        let now = Date()
        
        // Check if it's today
        if calendar.isDateInToday(date) {
            return "Today"
        }
        
        // Check if it's yesterday
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        
        // Check if it's from the current year
        let currentYear = calendar.component(.year, from: now)
        let messageYear = calendar.component(.year, from: date)
        
        let formatter = DateFormatter()
        
        if currentYear == messageYear {
            // Same year: "1st November" or "14 October"
            formatter.dateFormat = "d MMMM"
        } else {
            // Different year: "1st October 2024"
            formatter.dateFormat = "d MMMM yyyy"
        }
        
        let dayString = formatter.string(from: date)
        
        // Add ordinal suffix (1st, 2nd, 3rd, etc.)
        let day = calendar.component(.day, from: date)
        let ordinalDay = ordinalSuffix(for: day)
        
        // Replace the day number with ordinal version
        if currentYear == messageYear {
            formatter.dateFormat = "MMMM"
            let month = formatter.string(from: date)
            return "\(ordinalDay) \(month)"
        } else {
            formatter.dateFormat = "MMMM yyyy"
            let monthYear = formatter.string(from: date)
            return "\(ordinalDay) \(monthYear)"
        }
    }
    
    private func ordinalSuffix(for day: Int) -> String {
        let suffix: String
        switch day {
        case 1, 21, 31:
            suffix = "st"
        case 2, 22:
            suffix = "nd"
        case 3, 23:
            suffix = "rd"
        default:
            suffix = "th"
        }
        return "\(day)\(suffix)"
    }
}

// Helper function to determine if date separator should be shown
private func shouldShowDateSeparator(currentMessage: Message, previousMessage: Message?) -> Bool {
    guard let previous = previousMessage else {
        // First message - always show date
        return true
    }
    
    // Skip delimiter messages
    if currentMessage.id == "delimiter-new" || previous.id == "delimiter-new" {
        return false
    }
    
    let calendar = Calendar.current
    return !calendar.isDate(currentMessage.date, inSameDayAs: previous.date)
}

// MARK: - Chat Input
struct ChatInputView: View {
    @Binding var text: String
    let onSend: () -> Void
    let onSendMedia: (Data, String) -> Void
    let isEditing: Bool
    let editText: String?
    let onCancelEdit: () -> Void
    
    #if os(iOS)
    @State private var showImagePicker = false
    @State private var showDocumentPicker = false
    @State private var isRecordingAudio = false
    #endif
    
    var body: some View {
        VStack(spacing: 0) {
            if isEditing, let editText = editText {
                HStack {
                    Text("Editing: \(editText)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Cancel") {
                        onCancelEdit()
                    }
                    .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                #if os(iOS)
                .background(Color(uiColor: .systemGray6))
                #else
                .background(Color(NSColor.controlBackgroundColor))
                #endif
            }
            
            // Audio recorder when recording
                #if os(iOS)
            if isRecordingAudio {
                AudioRecorderView(
                    isRecording: $isRecordingAudio,
                    onAudioRecorded: { audioData, mimeType in
                        onSendMedia(audioData, mimeType)
                    },
                    onCancel: {
                        isRecordingAudio = false
                    }
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                inputView
            }
            #else
            inputView
            #endif
        }
        #if os(iOS)
        .animation(.easeInOut(duration: 0.3), value: isRecordingAudio)
        #endif
    }
    
    #if os(iOS)
    private var inputView: some View {
        HStack(spacing: 12) {
                Menu {
                Button(action: {
                        showImagePicker = true
                    }) {
                        Label("Photo or Video", systemImage: "photo")
                    }
                    Button(action: {
                        showDocumentPicker = true
                    }) {
                        Label("File", systemImage: "doc")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .sheet(isPresented: $showImagePicker) {
                    ImagePicker(onImageSelected: { imageData, mimeType in
                        onSendMedia(imageData, mimeType)
                    })
                }
                .sheet(isPresented: $showDocumentPicker) {
                    DocumentPicker(onDocumentSelected: { fileData, fileName, mimeType in
                        onSendMedia(fileData, mimeType)
                    })
                }
            
            // Audio recording button
                Button(action: {
                isRecordingAudio = true
            }) {
                Image(systemName: "mic.fill")
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.red)
                    .clipShape(Circle())
            }
            
            // Text input with web-like styling
                if #available(iOS 16.0, *) {
                    TextField("Type a message", text: $text, axis: .vertical)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.96, green: 0.97, blue: 0.99))
                    .cornerRadius(12)
                        .lineLimit(1...5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(text.isEmpty ? Color.clear : Color.blue.opacity(0.3), lineWidth: 1)
                    )
                } else {
                    TextField("Type a message", text: $text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.96, green: 0.97, blue: 0.99))
                    .cornerRadius(12)
                        .lineLimit(3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(text.isEmpty ? Color.clear : Color.blue.opacity(0.3), lineWidth: 1)
                    )
            }
            
            Button(action: {
                if !text.isEmpty {
                    onSend()
                }
            }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(text.isEmpty ? .gray : .blue)
            }
            .disabled(text.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
        .cornerRadius(15, corners: [.topLeft, .topRight])
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: -2)
                }
                #else
    private var inputView: some View {
        HStack(spacing: 12) {
            Button(action: {
                // File picker for macOS
            }) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            
                TextField("Type a message", text: $text)
                    .textFieldStyle(.roundedBorder)
                
                Button(action: {
                    if !text.isEmpty {
                        onSend()
                    }
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(text.isEmpty ? .gray : .blue)
                }
                .disabled(text.isEmpty)
            }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        }
        #endif
}

// MARK: - Media Message Preview
struct MediaMessagePreview: View {
    let message: Message
    let mimeType: String
    let isUser: Bool
    
    @State private var showFullScreen = false
    
    var body: some View {
        Group {
            if mimeType.starts(with: "image/") {
                ImagePreview(
                    imageURL: message.location ?? "",
                    previewURL: message.locationPreview,
                    fileName: message.originalName ?? message.fileName ?? "Image",
                    onTap: { showFullScreen = true }
                )
            } else if mimeType.starts(with: "video/") {
                VideoPreview(
                    videoURL: message.location ?? "",
                    fileName: message.originalName ?? message.fileName ?? "Video",
                    onTap: { showFullScreen = true }
                )
            } else if mimeType.contains("pdf") {
                PDFPreview(
                    fileURL: message.location ?? "",
                    fileName: message.originalName ?? message.fileName ?? "Document.pdf",
                    size: message.size,
                    onTap: { showFullScreen = true }
                )
            } else {
                FilePreview(
                    fileURL: message.location ?? "",
                    fileName: message.originalName ?? message.fileName ?? "File",
                    mimeType: mimeType,
                    size: message.size,
                    previewURL: message.locationPreview,
                    onTap: { showFullScreen = true }
                )
            }
        }
        .sheet(isPresented: $showFullScreen) {
            FilePreviewModal(
                message: message,
                onClose: { showFullScreen = false }
            )
        }
    }
}

// MARK: - Image Preview
struct ImagePreview: View {
    let imageURL: String
    let previewURL: String?
    let fileName: String
    let onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onTap) {
                AsyncImage(url: URL(string: previewURL ?? imageURL)) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: 150, height: 200)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: 150, maxHeight: 200)
                .clipped()
                .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Show file name
            if !fileName.isEmpty {
                Text(fileName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Video Preview
struct VideoPreview: View {
    let videoURL: String
    let fileName: String
    let onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onTap) {
                if let url = URL(string: videoURL) {
                    #if os(iOS)
                    VideoPlayer(player: AVPlayer(url: url))
                        .frame(width: 300, height: 200)
                        .cornerRadius(12)
                    #else
                    Text("Video preview")
                        .foregroundColor(.secondary)
                    #endif
                } else {
                    // Fallback if URL is invalid
                    HStack {
                        Image(systemName: "video.fill")
                            .font(.largeTitle)
                            .foregroundColor(.blue)
                        Text(fileName)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // Show file name
            if !fileName.isEmpty {
                Text(fileName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - PDF Preview
struct PDFPreview: View {
    let fileURL: String
    let fileName: String
    let size: String?
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "doc.fill")
                    .font(.largeTitle)
                    .foregroundColor(.red)
                VStack(alignment: .leading) {
                    Text(fileName)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if let size = size {
                        Text(formatFileSize(size))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - File Preview
struct FilePreview: View {
    let fileURL: String
    let fileName: String
    let mimeType: String
    let size: String?
    let previewURL: String?
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                if let previewURL = previewURL, let url = URL(string: previewURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            Image(systemName: "doc.fill")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            Image(systemName: "doc.fill")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                        @unknown default:
                            Image(systemName: "doc.fill")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                        }
                    }
                    .frame(width: 100, height: 60)
                    .clipped()
                    .cornerRadius(8)
                } else {
                    Image(systemName: "doc.fill")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                        .frame(width: 100, height: 60)
                }
                
                VStack(alignment: .leading) {
                    Text(fileName)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if let size = size {
                        Text(formatFileSize(size))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - File Preview Modal
struct FilePreviewModal: View {
    let message: Message
    let onClose: () -> Void
    
    @State private var isDownloading = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let mimeType = message.mimetype, let fileURL = message.location {
                    Group {
                        if mimeType.starts(with: "image/") {
                            FullScreenImageView(imageURL: fileURL, fileName: message.originalName ?? message.fileName ?? "Image")
                        } else if mimeType.starts(with: "video/") {
                            #if os(iOS)
                            FullScreenVideoView(videoURL: fileURL)
                            #else
                            Text("Video playback not available on macOS")
                                .foregroundColor(.secondary)
                            #endif
                        } else if mimeType.contains("pdf") {
                            PDFViewerView(pdfURL: fileURL)
                        } else {
                            UnsupportedFileView(
                                fileURL: fileURL,
                                fileName: message.originalName ?? message.fileName ?? "File",
                                mimeType: mimeType
                            )
                        }
                    }
                } else {
                    Text("Unable to load file")
                        .foregroundColor(.white)
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        onClose()
                    }
                    .foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: downloadFile) {
                        if isDownloading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.white)
                        }
                    }
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onClose()
                    }
                    .foregroundColor(.white)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: downloadFile) {
                        if isDownloading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.white)
                        }
                    }
                }
                #endif
            }
        }
    }
    
    private func downloadFile() {
        guard let fileURL = message.location, let url = URL(string: fileURL) else { return }
        
        isDownloading = true
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                
                #if os(iOS)
                // Save to Photos for images/videos, Files app for others
                if let mimeType = message.mimetype, mimeType.starts(with: "image/") {
                    if let image = UIImage(data: data) {
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    }
                } else if let mimeType = message.mimetype, mimeType.starts(with: "video/") {
                    // Save video to Photos
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    try data.write(to: tempURL)
                    // Note: Saving videos to Photos requires more complex handling
                } else {
                    // Save to Files app
                    let fileName = message.originalName ?? message.fileName ?? "file"
                    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let filePath = documentsPath.appendingPathComponent(fileName)
                    try data.write(to: filePath)
                }
                #endif
                
                isDownloading = false
                //print("✅ File downloaded successfully")
            } catch {
                isDownloading = false
                //print("❌ Download failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Full Screen Image View
struct FullScreenImageView: View {
    let imageURL: String
    let fileName: String
    
    var body: some View {
        AsyncImage(url: URL(string: imageURL)) { phase in
            switch phase {
            case .empty:
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .failure:
                VStack {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                    Text("Failed to load image")
                        .foregroundColor(.white)
                }
            @unknown default:
                EmptyView()
            }
        }
    }
}

// MARK: - Full Screen Video View
#if os(iOS)
struct FullScreenVideoView: View {
    let videoURL: String
    
    var body: some View {
        VideoPlayer(player: AVPlayer(url: URL(string: videoURL)!))
    }
}
#endif

// MARK: - PDF Viewer View
struct PDFViewerView: View {
    let pdfURL: String
    
    var body: some View {
        // For PDF, we'll show a web view or use PDFKit
        #if os(iOS)
        if let url = URL(string: pdfURL) {
            WebView(url: url)
        } else {
            Text("Unable to load PDF")
                .foregroundColor(.white)
        }
        #else
        Text("PDF viewer not implemented for macOS")
            .foregroundColor(.white)
        #endif
    }
}

// MARK: - Unsupported File View
struct UnsupportedFileView: View {
    let fileURL: String
    let fileName: String
    let mimeType: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.fill")
                .font(.system(size: 100))
                .foregroundColor(.white)
            
            VStack(spacing: 8) {
                Text("Unable to open the uploaded document")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("The file format is not supported by the system. Please upload a file in a compatible format. You still can download this file.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(16)
        }
    }
}

// MARK: - Helper Functions
func inferMimeType(from url: String) -> String {
    let urlLower = url.lowercased()
    
    // Check file extension
    if urlLower.hasSuffix(".jpg") || urlLower.hasSuffix(".jpeg") {
        return "image/jpeg"
    } else if urlLower.hasSuffix(".png") {
        return "image/png"
    } else if urlLower.hasSuffix(".gif") {
        return "image/gif"
    } else if urlLower.hasSuffix(".webp") {
        return "image/webp"
    } else if urlLower.hasSuffix(".mp4") {
        return "video/mp4"
    } else if urlLower.hasSuffix(".mov") {
        return "video/quicktime"
    } else if urlLower.hasSuffix(".avi") {
        return "video/x-msvideo"
    } else if urlLower.hasSuffix(".pdf") {
        return "application/pdf"
    } else if urlLower.hasSuffix(".doc") || urlLower.hasSuffix(".docx") {
        return "application/msword"
    } else if urlLower.hasSuffix(".xls") || urlLower.hasSuffix(".xlsx") {
        return "application/vnd.ms-excel"
    } else if urlLower.hasSuffix(".txt") {
        return "text/plain"
    }
    
    return ""
}

func formatFileSize(_ sizeString: String) -> String {
    guard let size = Int64(sizeString) else {
        return "Unknown size"
    }
    
    if size < 1024 {
        return "\(size) B"
    } else if size < 1024 * 1024 {
        return String(format: "%.2f KB", Double(size) / 1024.0)
    } else if size < 1024 * 1024 * 1024 {
        return String(format: "%.2f MB", Double(size) / (1024.0 * 1024.0))
    } else {
        return String(format: "%.2f GB", Double(size) / (1024.0 * 1024.0 * 1024.0))
    }
}

// MARK: - WebView for PDF (iOS only)
#if os(iOS)
struct WebView: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // No updates needed
    }
}
#endif

// MARK: - Image Picker (iOS)
#if os(iOS)
struct ImagePicker: UIViewControllerRepresentable {
    let onImageSelected: (Data, String) -> Void
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onImageSelected: onImageSelected)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onImageSelected: (Data, String) -> Void
        
        init(onImageSelected: @escaping (Data, String) -> Void) {
            self.onImageSelected = onImageSelected
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            guard let result = results.first else { return }
            
            if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                    guard let data = data, error == nil else { return }
                    DispatchQueue.main.async {
                        // Determine MIME type from UTType
                        var mimeType = "image/jpeg"
                        if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.png.identifier) {
                            mimeType = "image/png"
                        } else if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.heic.identifier) {
                            mimeType = "image/heic"
                        }
                        self.onImageSelected(data, mimeType)
                    }
                }
            } else if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.movie.identifier) { data, error in
                    guard let data = data, error == nil else { return }
                    DispatchQueue.main.async {
                        self.onImageSelected(data, "video/mp4")
                    }
                }
            }
        }
    }
}

// MARK: - Document Picker (iOS)
struct DocumentPicker: UIViewControllerRepresentable {
    let onDocumentSelected: (Data, String, String) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onDocumentSelected: onDocumentSelected)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onDocumentSelected: (Data, String, String) -> Void
        
        init(onDocumentSelected: @escaping (Data, String, String) -> Void) {
            self.onDocumentSelected = onDocumentSelected
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            // Start accessing security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                //print("❌ Failed to access security-scoped resource")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            do {
                let data = try Data(contentsOf: url)
                let fileName = url.lastPathComponent
                
                // Determine MIME type from file extension
                let mimeType: String
                let fileExtension = url.pathExtension.lowercased()
                switch fileExtension {
                case "pdf":
                    mimeType = "application/pdf"
                case "doc", "docx":
                    mimeType = "application/msword"
                case "xls", "xlsx":
                    mimeType = "application/vnd.ms-excel"
                case "txt":
                    mimeType = "text/plain"
                default:
                    mimeType = "application/octet-stream"
                }
                
                DispatchQueue.main.async {
                    self.onDocumentSelected(data, fileName, mimeType)
                }
            } catch {
                //print("❌ Failed to read file: \(error.localizedDescription)")
            }
        }
    }
}
#endif

// MARK: - Off-Clinic Hours Banner
struct OffClinicHoursBanner: View {
    @ObservedObject private var bannerStore = BannerSettingsStore.shared
    @State private var isActive = false
    @State private var timer: Timer?
    
    var body: some View {
        Group {
            if isActive {
                HStack {
                    Spacer()
                    Text(bannerStore.settings.bannerText)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    Spacer()
                }
                .background(Color.orange)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            checkAndUpdate()
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
        .onChange(of: bannerStore.settings.isEnabled) { _ in
            checkAndUpdate()
        }
        .onChange(of: bannerStore.settings.startHour) { _ in
            checkAndUpdate()
        }
        .onChange(of: bannerStore.settings.endHour) { _ in
            checkAndUpdate()
        }
        .onChange(of: bannerStore.settings.bannerText) { _ in
            checkAndUpdate()
        }
    }
    
    private func checkAndUpdate() {
        let newActive = bannerStore.settings.isCurrentlyActive()
        withAnimation(.easeInOut(duration: 0.3)) {
            isActive = newActive
        }
    }
    
    private func startTimer() {
        // Check every minute to update banner visibility
        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { _ in
            checkAndUpdate()
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

