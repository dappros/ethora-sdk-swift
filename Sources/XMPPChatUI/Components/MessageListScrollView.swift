//
//  MessageListScrollView.swift
//  XMPPChatUI
//
//  UIKit-based ScrollView wrapper for precise scroll position control
//  Enables exact scroll anchoring like Web version
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import XMPPChatCore

/// UIKit ScrollView wrapper for precise scroll control
/// Matches Web: content.scrollTop = newScrollTop
#if canImport(UIKit)
struct MessageListScrollView: UIViewRepresentable {
    @ObservedObject var viewModel: MessageListViewModel
    let currentUserId: String
    let currentUserXmppUsername: String?
    let config: ChatConfig?
    let messageViewBuilder: ((Message, Bool) -> AnyView)?
    
    // Scroll position tracking
    @Binding var scrollTop: CGFloat
    @Binding var scrollHeight: CGFloat
    
    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.showsVerticalScrollIndicator = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .never
        
        // Setup coordinator
        context.coordinator.scrollView = scrollView
        context.coordinator.setupScrollView()
        
        return scrollView
    }
    
    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        // CRITICAL: Capture scroll position BEFORE updating content (matches Web behavior)
        // This must happen BEFORE any content changes to get accurate "before" state
        let oldContentHeight = scrollView.contentSize.height
        let oldScrollOffset = scrollView.contentOffset.y
        let messageCountBefore = context.coordinator.lastMessageCount
        
        // Check if we need to restore scroll position after loading more messages
        if let scrollInfo = viewModel.getScrollPositionInfo(),
           let previousCount = viewModel.getPreviousMessageCount(),
           viewModel.messages.count > previousCount {
            // Save scroll info for restoration after content is laid out
            context.coordinator.savedScrollInfo = (top: scrollInfo.top, height: scrollInfo.height)
            context.coordinator.needsScrollRestoration = true
            
            print("📌 MessageListScrollView.updateUIView: Saved scroll info for restoration")
            print("   scrollTop: \(scrollInfo.top), scrollHeight: \(scrollInfo.height)")
            print("   previousCount: \(previousCount), currentCount: \(viewModel.messages.count)")
        } else if viewModel.messages.count > messageCountBefore {
            // If messages increased but we don't have saved scroll info, use current position
            // This handles cases where scroll position wasn't saved before loading
            print("📌 MessageListScrollView.updateUIView: Messages increased but no saved scroll info, using current position")
            print("   oldScrollOffset: \(oldScrollOffset), oldContentHeight: \(oldContentHeight)")
            print("   messageCountBefore: \(messageCountBefore), currentCount: \(viewModel.messages.count)")
            
            context.coordinator.savedScrollInfo = (top: oldScrollOffset, height: oldContentHeight)
            context.coordinator.needsScrollRestoration = true
        }
        
        // Update content (this will trigger layout and content size changes)
        context.coordinator.updateContent(
            messages: viewModel.messages,
            isLoadingMore: viewModel.isLoadingMore,
            currentUserId: currentUserId,
            currentUserXmppUsername: currentUserXmppUsername,
            config: config,
            messageViewBuilder: messageViewBuilder,
            oldContentHeight: oldContentHeight,
            oldScrollOffset: oldScrollOffset
        )
        
        // Update scroll metrics
        scrollTop = scrollView.contentOffset.y
        scrollHeight = scrollView.contentSize.height
    }
    
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: MessageListScrollView
        var scrollView: UIScrollView?
        var hostingController: UIHostingController<AnyView>?
        var scrollDebounceTask: Task<Void, Never>?
        var needsScrollRestoration: Bool = false
        var savedScrollInfo: (top: CGFloat, height: CGFloat)?
        var isRestoringScrollPosition: Bool = false
        var lastMessageCount: Int = 0
        var lastHistoryCheckAt: Date?
        
        /// Throttle interval for history load checks (milliseconds)
        private let historyCheckThrottleInterval: TimeInterval = 0.15 // 150ms
        
        init(_ parent: MessageListScrollView) {
            self.parent = parent
            super.init()
            setupNotificationObservers()
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
        
        private func setupNotificationObservers() {
            // Listen for messages loaded notification to restore scroll position
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleMessagesLoaded(_:)),
                name: NSNotification.Name("MessagesLoaded"),
                object: nil
            )
        }
        
        @objc private func handleMessagesLoaded(_ notification: Notification) {
            // When messages are loaded, ensure scroll position restoration happens
            // The restoration will be triggered by updateUIView -> updateContent flow
            // But we need to ensure the scroll info is available
            guard let scrollView = scrollView else { return }
            
            // Get scroll position info from view model
            if let scrollInfo = parent.viewModel.getScrollPositionInfo() {
                // Save scroll info for restoration
                savedScrollInfo = (top: scrollInfo.top, height: scrollInfo.height)
                needsScrollRestoration = true
                
                print("🔔 MessageListScrollView.handleMessagesLoaded: Saved scroll info for restoration")
                print("   top: \(scrollInfo.top), height: \(scrollInfo.height)")
                
                // Trigger update to restore scroll position
                DispatchQueue.main.async {
                    // Force update by triggering layout
                    scrollView.setNeedsLayout()
                    scrollView.layoutIfNeeded()
                }
            } else {
                print("⚠️ MessageListScrollView.handleMessagesLoaded: No scroll position info available")
            }
        }
        
        func setupScrollView() {
            guard let scrollView = scrollView else { return }
            
            // Create hosting controller for SwiftUI content
            let contentView = AnyView(EmptyView())
            hostingController = UIHostingController(rootView: contentView)
            hostingController?.view.backgroundColor = .clear
            
            if let hostingView = hostingController?.view {
                scrollView.addSubview(hostingView)
                hostingView.translatesAutoresizingMaskIntoConstraints = false
                
                // Constrain to scroll view's content area (not safe area, as contentInsetAdjustmentBehavior handles that)
                NSLayoutConstraint.activate([
                    hostingView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
                    hostingView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
                    hostingView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
                    hostingView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
                    hostingView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
                ])
            }
        }
        
        func updateContent(
            messages: [Message],
            isLoadingMore: Bool,
            currentUserId: String,
            currentUserXmppUsername: String?,
            config: ChatConfig?,
            messageViewBuilder: ((Message, Bool) -> AnyView)?,
            oldContentHeight: CGFloat,
            oldScrollOffset: CGFloat
        ) {
            guard let hostingController = hostingController,
                  let scrollView = scrollView else { return }
            
            // Track message count change
            let messagesIncreased = messages.count > lastMessageCount
            lastMessageCount = messages.count
            
            // Build message list view using VStack (UIScrollView handles scrolling)
            let messageList = VStack(spacing: 8) {
                if isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                }
                
                ForEach(messages) { message in
                    if message.id == "delimiter-new" {
                        NewMessageLabel()
                            .padding(.vertical, 8)
                    } else {
                        let isUser = self.isCurrentUser(message, currentUserId: currentUserId, currentUserXmppUsername: currentUserXmppUsername)
                        
                        if let customView = messageViewBuilder {
                            customView(message, isUser)
                        } else {
                            MessageBubbleView(
                                message: message,
                                isUser: isUser,
                                showAvatar: true,
                                previousMessage: nil,
                                onLongPress: {},
                                onRetry: nil,
                                onReactionTap: { _ in },
                                onReply: {},
                                onEdit: nil,
                                onDelete: nil,
                                onReport: nil,
                                onMediaTap: nil
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            hostingController.rootView = AnyView(messageList)
            
            // CRITICAL: Update content size and restore scroll position in one operation
            // This prevents any intermediate scroll jumps
            DispatchQueue.main.async {
                hostingController.view.setNeedsLayout()
                hostingController.view.layoutIfNeeded()
                
                // Calculate new content size
                let fittingSize = hostingController.view.systemLayoutSizeFitting(
                    CGSize(width: scrollView.bounds.width, height: UIView.layoutFittingExpandedSize.height),
                    withHorizontalFittingPriority: .required,
                    verticalFittingPriority: .fittingSizeLevel
                )
                let newContentHeight = max(fittingSize.height, scrollView.bounds.height)
                
                // CRITICAL: If messages increased (prepended), restore scroll position
                // This matches Web: newScrollTop = currentTop + (content.scrollHeight - previousHeight)
                if messagesIncreased && self.needsScrollRestoration,
                   let scrollInfo = self.savedScrollInfo {
                    print("🔄 MessageListScrollView.updateContent: Restoring scroll position after messages loaded")
                    print("   Old scrollTop: \(scrollInfo.top), Old height: \(scrollInfo.height)")
                    print("   New height: \(newContentHeight)")
                    print("   Messages increased: \(messagesIncreased)")
                    
                    // Set flag to prevent scroll handling during restoration
                    self.isRestoringScrollPosition = true
                    
                    // If oldTop was extremely small (< 5px), skip explicit scroll restoration
                    // User is already pinned at the very top, natural prepend will maintain position
                    if scrollInfo.top < 5 {
                        print("   User at very top (< 5px), skipping explicit restoration")
                        // No restoration needed, just update content size
                        scrollView.contentSize = CGSize(width: scrollView.bounds.width, height: newContentHeight)
                        
                        // Clear restoration flags
                        self.savedScrollInfo = nil
                        self.needsScrollRestoration = false
                        self.isRestoringScrollPosition = false
                        
                        // Clear scroll position info in view model
                        self.parent.viewModel.clearScrollPositionInfo()
                        
                        // Still check if should continue loading
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            self.checkIfShouldContinueLoading(scrollView: scrollView)
                        }
                    } else {
                        // Calculate height difference
                        let heightDifference = newContentHeight - scrollInfo.height
                        
                        // Calculate new scroll position (matches Web exactly)
                        // newScrollTop = currentTop + (content.scrollHeight - previousHeight)
                        let newScrollTop = scrollInfo.top + heightDifference
                        
                        print("   Height difference: \(heightDifference)")
                        print("   Calculated newScrollTop: \(newScrollTop)")
                        
                        // Set content size first
                        scrollView.contentSize = CGSize(width: scrollView.bounds.width, height: newContentHeight)
                        
                        // Wait a frame for content size to be applied, then restore scroll position
                        DispatchQueue.main.async {
                            // Immediately restore scroll position (no animation to prevent jump)
                            // This matches Web: content.scrollTop = newScrollTop
                            let maxScrollTop = max(0, scrollView.contentSize.height - scrollView.bounds.height)
                            let clampedScrollTop = min(max(newScrollTop, 0), maxScrollTop)
                            
                            print("   Max scrollTop: \(maxScrollTop)")
                            print("   Clamped scrollTop: \(clampedScrollTop)")
                            print("   Setting scroll position...")
                            
                            scrollView.setContentOffset(CGPoint(x: 0, y: clampedScrollTop), animated: false)
                            
                            // Verify scroll position was set
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                let actualScrollTop = scrollView.contentOffset.y
                                print("   ✅ Scroll position restored. Actual scrollTop: \(actualScrollTop)")
                                
                                // Clear restoration flags
                                self.savedScrollInfo = nil
                                self.needsScrollRestoration = false
                                
                                // Clear scroll position info in view model
                                self.parent.viewModel.clearScrollPositionInfo()
                                
                                // After restoration, check if should continue loading
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    self.isRestoringScrollPosition = false
                                    self.checkIfShouldContinueLoading(scrollView: scrollView)
                                }
                            }
                        }
                    }
                } else {
                    // No restoration needed, just update content size
                    if messagesIncreased {
                        print("⚠️ MessageListScrollView.updateContent: Messages increased but scroll restoration not triggered")
                        print("   needsScrollRestoration: \(self.needsScrollRestoration)")
                        print("   savedScrollInfo: \(self.savedScrollInfo != nil ? "exists" : "nil")")
                    }
                    scrollView.contentSize = CGSize(width: scrollView.bounds.width, height: newContentHeight)
                }
            }
        }
        
        
        /// Check if should continue loading after messages are prepended
        /// Matches Web: recursive check after scroll restoration
        /// This ensures continuous loading until historyComplete or user scrolls away
        private func checkIfShouldContinueLoading(scrollView: UIScrollView) {
            // CRITICAL: Check auto-load mode and limits
            guard parent.viewModel.isAutoLoadInProgress else {
                print("ℹ️ MessageListScrollView.checkIfShouldContinueLoading: auto-load not in progress, skipping")
                return
            }
            guard parent.viewModel.currentConsecutiveAutoLoads < parent.viewModel.maxAutoLoads else {
                // Max consecutive loads reached - reset and require user interaction
                print("⚠️ MessageListScrollView.checkIfShouldContinueLoading: auto-load limit reached (\(parent.viewModel.currentConsecutiveAutoLoads)/\(parent.viewModel.maxAutoLoads)), resetting tracking")
                parent.viewModel.resetAutoLoadTracking()
                return
            }
            
            // CRITICAL: Check both conditions (matches Web: !isLoadingMore && !historyComplete)
            guard !parent.viewModel.isLoadingMore else {
                print("ℹ️ MessageListScrollView.checkIfShouldContinueLoading: isLoadingMore == true, skipping")
                return
            }
            guard !parent.viewModel.isHistoryComplete else {
                print("ℹ️ MessageListScrollView.checkIfShouldContinueLoading: history is complete, resetting auto-load tracking")
                parent.viewModel.resetAutoLoadTracking()
                return
            }
            
            // Get current scroll position
            let scrollTop = scrollView.contentOffset.y
            
            // If user is still at top (< 150px threshold), trigger another load
            // This ensures we keep loading until either:
            // 1. History is complete (historyComplete = true)
            // 2. User scrolls away from top (scrollTop >= 150)
            // 3. Max consecutive auto-loads reached
            if scrollTop < 150 {
                print("🔁 MessageListScrollView.checkIfShouldContinueLoading: user still near top (scrollTop=\(scrollTop)), triggering next auto history load")
                // Save scroll position before loading again
                let scrollHeight = scrollView.contentSize.height
                parent.viewModel.saveScrollPosition(top: scrollTop, height: scrollHeight)
                
                // Also save in coordinator for immediate use
                self.savedScrollInfo = (top: scrollTop, height: scrollHeight)
                self.needsScrollRestoration = true
                
                print("💾 MessageListScrollView.checkIfShouldContinueLoading: Saved scroll position for next load")
                print("   top: \(scrollTop), height: \(scrollHeight)")
                
                // Trigger another load as auto-load (this will continue until historyComplete or limit reached)
                parent.viewModel.fetchHistory(isAutoLoad: true)
            } else {
                // User scrolled away - reset auto-load tracking
                print("ℹ️ MessageListScrollView.checkIfShouldContinueLoading: user scrolled away from top (scrollTop=\(scrollTop)), resetting auto-load tracking")
                parent.viewModel.resetAutoLoadTracking()
            }
        }
        
        private func isCurrentUser(_ message: Message, currentUserId: String, currentUserXmppUsername: String?) -> Bool {
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
        
        // MARK: - UIScrollViewDelegate
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            // Don't handle scroll events during restoration to prevent interference
            guard !isRestoringScrollPosition else {
                return
            }
            
            // Update parent scroll metrics
            parent.scrollTop = scrollView.contentOffset.y
            parent.scrollHeight = scrollView.contentSize.height
            
            // Throttle scroll handling using timestamp-based throttling
            let now = Date()
            if let lastCheck = lastHistoryCheckAt,
               now.timeIntervalSince(lastCheck) < historyCheckThrottleInterval {
                // Too soon since last check - skip
                return
            }
            
            // Update last check timestamp
            lastHistoryCheckAt = now
            
            // Check if should load more messages
            checkIfLoadMoreMessages(scrollView: scrollView)
        }
        
        /// Check if should load more messages (matches Web checkIfLoadMoreMessages)
        /// TypeScript: if (params.top >= 150 || isLoadingMore.current) return;
        private func checkIfLoadMoreMessages(scrollView: UIScrollView) {
            // CRITICAL: Check both conditions (matches Web: !isLoadingMore && !historyComplete)
            guard !parent.viewModel.isLoadingMore else {
                print("ℹ️ MessageListScrollView.checkIfLoadMoreMessages: isLoadingMore == true, not requesting more history")
                return
            }
            guard !parent.viewModel.isHistoryComplete else {
                print("ℹ️ MessageListScrollView.checkIfLoadMoreMessages: history is complete, no more history requests")
                return
            }
            
            // Don't check during scroll restoration
            guard !isRestoringScrollPosition else { return }
            
            // Don't check if scroll view is not being actively dragged/decelerated during programmatic restoration
            // This prevents double triggers during restoration
            if !scrollView.isDragging && !scrollView.isDecelerating && isRestoringScrollPosition {
                return
            }
            
            // Get scroll position
            let scrollTop = scrollView.contentOffset.y
            let scrollHeight = scrollView.contentSize.height
            
            print("🌀 MessageListScrollView.checkIfLoadMoreMessages: scrollTop=\(scrollTop), scrollHeight=\(scrollHeight)")
            
            // Guard: Only trigger when near top (scrollTop < 150px) - matches TypeScript
            // Web uses 150px threshold
            guard scrollTop < 150 else {
                // User scrolled away from top - reset auto-load tracking
                print("ℹ️ MessageListScrollView.checkIfLoadMoreMessages: user not near top (scrollTop=\(scrollTop)), resetting auto-load tracking")
                parent.viewModel.resetAutoLoadTracking()
                return
            }
            
            // CRITICAL: Save scroll position before loading (for scroll anchoring)
            // This matches Web: scrollParams.current = getScrollParams()
            // This must happen BEFORE fetchHistory() is called
            parent.viewModel.saveScrollPosition(top: scrollTop, height: scrollHeight)
            print("💾 MessageListScrollView.checkIfLoadMoreMessages: Saved scroll position before load")
            print("   top: \(scrollTop), height: \(scrollHeight)")
            
            // Also save in coordinator for immediate use (we're inside Coordinator, so use self)
            self.savedScrollInfo = (top: scrollTop, height: scrollHeight)
            self.needsScrollRestoration = true
            
            // Fetch history (load more messages) - mark as manual load (not auto-load)
            print("🚀 MessageListScrollView.checkIfLoadMoreMessages: requesting more history (manual), scrollTop=\(scrollTop)")
            parent.viewModel.fetchHistory(isAutoLoad: false)
        }
    }
}
#else
struct MessageListScrollView: View {
    @ObservedObject var viewModel: MessageListViewModel
    let currentUserId: String
    let currentUserXmppUsername: String?
    let config: ChatConfig?
    let messageViewBuilder: ((Message, Bool) -> AnyView)?

    @Binding var scrollTop: CGFloat
    @Binding var scrollHeight: CGFloat

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if viewModel.isLoadingMore {
                    ProgressView().padding()
                }
                ForEach(viewModel.messages) { message in
                    if message.id == "delimiter-new" {
                        NewMessageLabel().padding(.vertical, 8)
                    } else {
                        let isUser = isCurrentUser(message)
                        if let customView = messageViewBuilder {
                            customView(message, isUser)
                        } else {
                            MessageBubbleView(
                                message: message,
                                isUser: isUser,
                                showAvatar: true,
                                previousMessage: nil,
                                onLongPress: {},
                                onRetry: nil,
                                onReactionTap: { _ in },
                                onReply: {},
                                onEdit: nil,
                                onDelete: nil,
                                onReport: nil,
                                onMediaTap: nil
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            scrollHeight = proxy.size.height
                            scrollTop = 0
                        }
                        .onChange(of: proxy.size.height) { newHeight in
                            scrollHeight = newHeight
                        }
                }
            )
        }
    }

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
}
#endif
