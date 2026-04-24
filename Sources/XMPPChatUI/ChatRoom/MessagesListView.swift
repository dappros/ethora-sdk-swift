//
//  MessagesListView.swift
//  XMPPChatUI
//

import SwiftUI
import XMPPChatCore

struct MessagesListView: View {
    @ObservedObject var viewModel: ChatRoomViewModel
    @Binding var messageText: String
    @Binding var selectedMessageForThread: Message?
    @Binding var showThread: Bool
    @Binding var selectedMediaMessage: Message?
    @Binding var showFullScreenImage: Bool
    @Binding var showFullScreenVideo: Bool
    @Binding var showFullScreenPDF: Bool
    @Binding var messageToReport: Message?
    @Binding var showReportModal: Bool
    
    let proxy: ScrollViewProxy
    
    var body: some View {
        LazyVStack(spacing: 8) {
            // Error message banner
            if let errorMessage = viewModel.loadError {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(errorMessage)
                            .font(.caption)
                        Spacer()
                        Button(action: {
                            viewModel.loadError = nil
                            viewModel.loadMessages(forceReload: true)
                        }) {
                            Text("Retry")
                                .font(.caption)
                                .fontWeight(.semibold)
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
            
            // Loader at top
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
            
            let filteredMessages = filteredMessagesList()
            
            ForEach(Array(filteredMessages.enumerated()), id: \.element.id) { index, message in
                let previousMessage = index > 0 ? filteredMessages[index - 1] : nil
                let nextMessage = index < filteredMessages.count - 1 ? filteredMessages[index + 1] : nil
                
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
                
                if showDateSeparator {
                    DateSeparatorView(date: message.date)
                        .padding(.vertical, 8)
                }
                
                let isUser = isMessageFromCurrentUser(message)
                
                MessageBubbleView(
                    message: message,
                    isUser: isUser,
                    showAvatar: showAvatar,
                    previousMessage: previousMessage,
                    onLongPress: nil,
                    onRetry: {
                        if message.pending == false && message.xmppId == nil {
                            viewModel.resendMessage(message)
                        }
                    },
                    onReactionTap: { emoji in
                        viewModel.addReaction(messageId: message.id, emoji: emoji)
                    },
                    onReply: {
                        selectedMessageForThread = message
                        showThread = true
                    },
                    onEdit: {
                        viewModel.isEditing = true
                        viewModel.editText = message.body
                        viewModel.editMessageId = message.id
                        messageText = message.body
                    },
                    onDelete: {
                        viewModel.deleteMessage(message.id)
                    },
                    onReport: {
                        messageToReport = message
                        showReportModal = true
                    },
                    onMediaTap: { mediaMessage in
                        selectedMediaMessage = mediaMessage
                        handleMediaTap(mediaMessage)
                    }
                )
                .id(message.id)
            }
            
            // Visual padding below the last message so it never sits flush
            // against the input bar. `ScrollViewReader.scrollTo(bottomAnchorID,
            // anchor: .bottom)` aligns this sentinel with the visible bottom,
            // giving the bubble above a comfortable breathing room and
            // absorbing any off-by-one that LazyVStack can introduce while
            // it incrementally measures the final row.
            Color.clear
                .frame(height: 16)
                .id("bottom-anchor")
        }
    }
    
    private func filteredMessagesList() -> [Message] {
        return viewModel.messages.filter { msg in
            guard !msg.body.isEmpty else { return false }
            guard msg.isDeleted != true else { return false }
            
            let showInChannel = msg.showInChannel == "true"
            let isNotReply = msg.isReply != true && (msg.isReply == nil || msg.isReply == false)
            let hasNoMainMessage = msg.mainMessage == nil || msg.mainMessage?.isEmpty == true
            let shouldShow = showInChannel || (isNotReply && hasNoMainMessage)
            
            guard shouldShow else { return false }
            
            if let pending = msg.pending, pending {
                let hasConfirmedVersion = viewModel.messages.contains { otherMsg in
                    guard otherMsg.pending != true else { return false }
                    
                    if otherMsg.id == msg.id ||
                       (otherMsg.xmppId != nil && otherMsg.xmppId == msg.id) ||
                       (msg.xmppId != nil && msg.xmppId == otherMsg.id) ||
                       (otherMsg.xmppId != nil && msg.xmppId != nil && otherMsg.xmppId == msg.xmppId) {
                        return true
                    }
                    
                    if otherMsg.body == msg.body &&
                       (otherMsg.user.id == msg.user.id || 
                        otherMsg.user.xmppUsername == msg.user.xmppUsername) {
                        return true
                    }
                    
                    return false
                }
                return !hasConfirmedVersion
            }
            
            return true
        }
    }
    
    private func isMessageFromCurrentUser(_ message: Message) -> Bool {
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
        return isCurrentUserById || isCurrentUserByXmpp
    }
    
    private func handleMediaTap(_ mediaMessage: Message) {
        let mimeType: String = {
            if let existingMimeType = mediaMessage.mimetype, !existingMimeType.isEmpty {
                return existingMimeType
            } else if let location = mediaMessage.location {
                return inferMimeType(from: location)
            } else {
                return "application/octet-stream"
            }
        }()
        
        if mimeType.hasPrefix("image/") {
            showFullScreenImage = true
        } else if mimeType.hasPrefix("video/") {
            showFullScreenVideo = true
        } else if mimeType.contains("pdf") {
            showFullScreenPDF = true
        }
    }
}
