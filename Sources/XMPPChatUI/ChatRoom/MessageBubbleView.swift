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
    /// Local-only removal for messages that were flagged failed and never
    /// reached the server. Distinct from `onDelete`, which sends `<delete/>`
    /// to the server.
    var onDiscard: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    
    private var bubbleStyle: MessageBubbleStyle? { ConfigStore.shared.config.bubleMessage }
    
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
                    if isUser, message.failed != true, let pending = message.pending, pending {
                        Text("sending...")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    if isUser, message.failed == true {
                        Text("not sent")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }

                    Text(message.date, style: .time)
                        .font(.caption2)
                        .foregroundColor(isUser ? .white.opacity(0.7) : .secondary)

                    if isUser {
                        MessageStatusIndicatorView(
                            message: message,
                            onRetry: onRetry,
                            onDiscard: onDiscard
                        )
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isUser ? outgoingBubbleBackground() : incomingBubbleBackground())
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
                        foregroundColor: messageTextColor
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
                .frame(maxWidth: chatBubbleMaxWidth(), alignment: isUser ? .trailing : .leading)
                
                if !isUser {
                    Spacer()
                }
            }
            .padding(.horizontal, 10)
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
    
    private func outgoingBubbleBackground() -> Color {
        if let configured = bubbleStyle?.backgroundMessageUser, !configured.isEmpty {
            return Color(hex: configured)
        }
        if let primary = ConfigStore.shared.config.colors?.primary, !primary.isEmpty {
            let color = Color(hex: primary)
            return colorScheme == .dark ? color.opacity(0.82) : color
        }
        return colorScheme == .dark
            ? Color(red: 0.07, green: 0.42, blue: 0.84)
            : Color.blue
    }
    
    private func incomingBubbleBackground() -> Color {
        if let configured = bubbleStyle?.backgroundMessage, !configured.isEmpty {
            return Color(hex: configured)
        }
        return chatIncomingBubbleBackground()
    }
    
    private var messageTextColor: Color {
        if isUser {
            if let configured = bubbleStyle?.colorUser, !configured.isEmpty {
                return Color(hex: configured)
            }
            return .white
        }
        if let configured = bubbleStyle?.color, !configured.isEmpty {
            return Color(hex: configured)
        }
        return .primary
    }
}

struct MessageStatusIndicatorView: View {
    let message: Message
    let onRetry: (() -> Void)?
    var onDiscard: (() -> Void)? = nil

    @State private var showFailedActions = false

    var body: some View {
        Group {
            if message.failed == true {
                Button(action: { showFailedActions = true }) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
                .confirmationDialog(
                    "Message not sent",
                    isPresented: $showFailedActions,
                    titleVisibility: .visible
                ) {
                    if onRetry != nil {
                        Button("Resend") { onRetry?() }
                    }
                    if onDiscard != nil {
                        Button("Delete", role: .destructive) { onDiscard?() }
                    }
                    Button("Cancel", role: .cancel) {}
                }
            } else if let pending = message.pending, pending {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
            } else if message.xmppId != nil {
                ZStack {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                        .foregroundColor(.green)
                        .offset(x: 0, y: 0)
                    Image(systemName: "checkmark")
                        .font(.caption2)
                        .foregroundColor(.green)
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
