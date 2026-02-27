//
//  MessageBubbleView.swift
//  XMPPChatUI
//

import SwiftUI
import XMPPChatCore

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
    let onMediaTap: ((Message) -> Void)?
    
    @State private var showContextMenu = false
    @State private var showReactionPicker = false
    
    var body: some View {
        if message.id == "delimiter-new" {
            return AnyView(
                UnreadMessagesDelimiter()
            )
        }
        
        let isConsecutive = previousMessage?.user.id == message.user.id
        
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
            
        @ViewBuilder
        func buildMessageContent() -> some View {
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if !isUser && (!isConsecutive || !showAvatar) {
                    Text(message.user.fullName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(isUser ? .white.opacity(0.8) : .blue)
                }
                
                buildMediaOrTextContent()
                
                if let reactions = message.reaction, !reactions.isEmpty {
                    ReactionBadgesView(reactions: reactions)
                        .padding(.top, 4)
                }
                
                HStack(spacing: 4) {
                    if !isUser {
                        Spacer()
                    }
                    
                    if isUser, let pending = message.pending, pending {
                        Text("sending...")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    Text(message.date, style: .time)
                        .font(.caption2)
                        .foregroundColor(isUser ? .white.opacity(0.7) : .secondary)
                    
                    if isUser {
                        MessageStatusIndicatorView(message: message, onRetry: onRetry)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isUser ? Color.blue : chatIncomingBubbleBackground())
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
                    isUser: isUser,
                    onMediaTap: { mediaMessage in
                        onMediaTap?(mediaMessage)
                    }
                )
            } else {
                if message.body.lowercased() != "media" {
                    UniversalMarkdownTextView(
                        text: message.body,
                        foregroundColor: isUser ? .white : .primary
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(isUser ? .trailing : .leading)
                    .lineLimit(nil)
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
                                            copyToClipboard(message.body)
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
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            buildMessageContent()
                                .contextMenu {
                                    MessageContextMenuItems(
                                        message: message,
                                        isUser: isUser,
                                        onReply: onReply,
                                        onCopy: {
                                            copyToClipboard(message.body)
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
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: chatBubbleMaxWidth(), alignment: isUser ? .trailing : .leading)
                
                if !isUser {
                    Spacer()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
        )
    }
    
    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

struct MessageStatusIndicatorView: View {
    let message: Message
    let onRetry: (() -> Void)?
    
    var body: some View {
        Group {
            if let pending = message.pending, pending {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
            } else if message.xmppId == nil && message.pending == false {
                Button(action: {
                    onRetry?()
                }) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            } else if message.xmppId != nil {
                ZStack {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                        .offset(x: 0, y: 0)
                    Image(systemName: "checkmark")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                        .offset(x: 3, y: 0)
                }
                .frame(width: 16, height: 12)
            } else {
                Image(systemName: "checkmark")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
}

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
        }
    }
}
