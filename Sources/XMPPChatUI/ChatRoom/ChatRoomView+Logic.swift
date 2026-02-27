//
//  ChatRoomView+Logic.swift
//  XMPPChatUI
//

import SwiftUI
import XMPPChatCore

extension ChatRoomView {
    func handleScroll(metrics: ScrollMetrics, proxy: ScrollViewProxy) {
        scrollHeight = metrics.scrollHeight
        scrollTop = metrics.scrollTop
        clientHeight = metrics.clientHeight
        
        let isAtBottom = scrollHeight - scrollTop - clientHeight < 100
        atBottom = isAtBottom
        
        withAnimation {
            showScrollButton = !isAtBottom
            isUserScrolledUp = !isAtBottom
        }
        
        if isAtBottom {
            newMessagesCount = 0
        }
        
        checkIfLoadMoreMessages(metrics: metrics)
    }
    
    func checkIfLoadMoreMessages(metrics: ScrollMetrics) {
        guard allowLoadMore, !viewModel.isLoadingMore, viewModel.hasMoreMessages else { return }
        
        let now = Date()
        if let lastCheck = lastHistoryCheckAt, now.timeIntervalSince(lastCheck) < historyCheckThrottleInterval {
            return
        }
        lastHistoryCheckAt = now
        
        if metrics.scrollTop < 200 {
            if let firstMsg = viewModel.messages.first {
                viewModel.saveScrollPosition(messageId: firstMsg.id, index: 0)
            }
            viewModel.loadMoreMessages()
        }
    }
    
    func handleMessagesLoaded(_ notification: Notification, proxy: ScrollViewProxy) {
        let userInfo = notification.userInfo ?? [:]
        let oldCount = userInfo["oldCount"] as? Int ?? 0
        let newCount = userInfo["newCount"] as? Int ?? viewModel.messages.count
        
        if let scrollInfo = viewModel.getScrollPositionInfo() {
            if newCount > oldCount {
                if let _ = viewModel.messages.firstIndex(where: { $0.id == scrollInfo.messageId }) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(scrollInfo.messageId, anchor: .top)
                        }
                        viewModel.clearScrollPositionInfo()
                    }
                } else {
                    viewModel.clearScrollPositionInfo()
                }
            } else {
                viewModel.clearScrollPositionInfo()
            }
        }
    }
    
    func handleMessageCountChange(_ newCount: Int, proxy: ScrollViewProxy) {
        guard newCount > 0 else { return }
        
        if newCount > lastMessageCount {
            let lastMessage = viewModel.messages.last
            let isLastMessageFromUser = lastMessage != nil && isUserMessage(lastMessage!)
            
            if !isLastMessageFromUser && isUserScrolledUp {
                newMessagesCount += 1
            }
            
            if isLastMessageFromUser {
                scrollToBottom(proxy: proxy)
            }
        }
        lastMessageCount = newCount
        
        if viewModel.isLoadingMore { return }

        if needsInitialScroll {
            scrollToBottom(proxy: proxy)
            needsInitialScroll = false
            allowLoadMore = true
            return
        }
        
        if viewModel.shouldScrollToBottom(), let _ = viewModel.messages.last {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo("bottom-anchor", anchor: .bottom)
                }
                viewModel.setShouldScrollToBottom(false)
            }
        }
    }
    
    func isUserMessage(_ message: Message) -> Bool {
        if message.user.id == viewModel.currentUserId { return true }
        if let currentUserXmpp = viewModel.currentUserXmppUsername,
           let messageUserXmpp = message.user.xmppUsername {
            return currentUserXmpp.lowercased().trimmingCharacters(in: .whitespaces) == 
                   messageUserXmpp.lowercased().trimmingCharacters(in: .whitespaces)
        }
        return false
    }
    
    func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.3)) {
            proxy.scrollTo("bottom-anchor", anchor: .bottom)
        }
        newMessagesCount = 0
        atBottom = true
        showScrollButton = false
    }
    
    func dismissKeyboard() {
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}
