//
//  MessageListScrollView.swift
//  XMPPChatUI
//
//  UIKit-based ScrollView wrapper for precise scroll position control
//  Enables exact scroll anchoring like Web version
//

import SwiftUI
import UIKit
import XMPPChatCore

/// UIKit ScrollView wrapper for precise scroll control
/// Matches Web: content.scrollTop = newScrollTop
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
        } else if viewModel.messages.count > messageCountBefore {
            // If messages increased but we don't have saved scroll info, use current position
            // This handles cases where scroll position wasn't saved before loading
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
            // Scroll restoration now happens in updateContent when messages change
            // This notification is just for tracking - the actual restoration
            // is triggered by the updateUIView -> updateContent flow
            // No action needed here as updateContent handles everything
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
                    // Set flag to prevent scroll handling during restoration
                    self.isRestoringScrollPosition = true
                    
                    // Calculate height difference
                    let heightDifference = newContentHeight - scrollInfo.height
                    
                    // Calculate new scroll position (matches Web exactly)
                    // newScrollTop = currentTop + (content.scrollHeight - previousHeight)
                    let newScrollTop = scrollInfo.top + heightDifference
                    
                    // Set content size first
                    scrollView.contentSize = CGSize(width: scrollView.bounds.width, height: newContentHeight)
                    
                    // Immediately restore scroll position (no animation to prevent jump)
                    // This matches Web: content.scrollTop = newScrollTop
                    let maxScrollTop = max(0, scrollView.contentSize.height - scrollView.bounds.height)
                    let clampedScrollTop = min(max(newScrollTop, 0), maxScrollTop)
                    scrollView.setContentOffset(CGPoint(x: 0, y: clampedScrollTop), animated: false)
                    
                    // Clear restoration flags
                    self.savedScrollInfo = nil
                    self.needsScrollRestoration = false
                    
                    // Clear scroll position info in view model
                    self.parent.viewModel.clearScrollPositionInfo()
                    
                    // After restoration, check if should continue loading
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        self.isRestoringScrollPosition = false
                        self.checkIfShouldContinueLoading(scrollView: scrollView)
                    }
                } else {
                    // No restoration needed, just update content size
                    scrollView.contentSize = CGSize(width: scrollView.bounds.width, height: newContentHeight)
                }
            }
        }
        
        
        /// Check if should continue loading after messages are prepended
        /// Matches Web: recursive check after scroll restoration
        /// This ensures continuous loading until historyComplete or user scrolls away
        private func checkIfShouldContinueLoading(scrollView: UIScrollView) {
            // CRITICAL: Check both conditions (matches Web: !isLoadingMore && !historyComplete)
            guard !parent.viewModel.isLoadingMore else { return }
            guard !parent.viewModel.isHistoryComplete else { return }
            
            // Get current scroll position
            let scrollTop = scrollView.contentOffset.y
            
            // If user is still at top (< 150px threshold), trigger another load
            // This ensures we keep loading until either:
            // 1. History is complete (historyComplete = true)
            // 2. User scrolls away from top (scrollTop >= 150)
            if scrollTop < 150 {
                // Save scroll position before loading again
                let scrollHeight = scrollView.contentSize.height
                parent.viewModel.saveScrollPosition(top: scrollTop, height: scrollHeight)
                
                // Trigger another load (this will continue until historyComplete)
                parent.viewModel.fetchHistory()
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
            
            // Debounce scroll handling (matches Web: 50ms timeout)
            scrollDebounceTask?.cancel()
            scrollDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                
                guard !Task.isCancelled else { return }
                
                // Check if should load more messages
                checkIfLoadMoreMessages(scrollView: scrollView)
            }
        }
        
        /// Check if should load more messages (matches Web checkIfLoadMoreMessages)
        /// TypeScript: if (params.top >= 150 || isLoadingMore.current) return;
        private func checkIfLoadMoreMessages(scrollView: UIScrollView) {
            // CRITICAL: Check both conditions (matches Web: !isLoadingMore && !historyComplete)
            guard !parent.viewModel.isLoadingMore else { return }
            guard !parent.viewModel.isHistoryComplete else { return }
            
            // Don't check during scroll restoration
            guard !isRestoringScrollPosition else { return }
            
            // Get scroll position
            let scrollTop = scrollView.contentOffset.y
            let scrollHeight = scrollView.contentSize.height
            
            // Guard: Only trigger when near top (scrollTop < 150px) - matches TypeScript
            // Web uses 150px threshold
            guard scrollTop < 150 else { return }
            
            // Save scroll position before loading (for scroll anchoring)
            // This matches Web: scrollParams.current = getScrollParams()
            parent.viewModel.saveScrollPosition(top: scrollTop, height: scrollHeight)
            
            // Fetch history (load more messages)
            parent.viewModel.fetchHistory()
        }
    }
}
