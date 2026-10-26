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
    /// Tap on one tile of a multi-file album: the message and the tapped file's index.
    /// Falls back to `onMediaTap` (index 0) when not set.
    var onAlbumTap: ((Message, Int) -> Void)? = nil
    /// Delivery tick for our own messages (see `ReceiptState`).
    var receiptState: ReceiptState = .sent
    /// Local-only removal for messages that were flagged failed and never
    /// reached the server. Distinct from `onDelete`, which sends `<delete/>`
    /// to the server.
    var onDiscard: (() -> Void)? = nil
    /// Thread context: the thread panel's own list. No quote and no reply pill,
    /// and the "Reply" menu item is hidden (web `isReply`).
    var inThread: Bool = false
    /// Thread replies whose parent is this message, for the reply pill.
    var threadReplies: [Message] = []
    /// Localpart of the current user, the key reactions are stored under.
    var currentReactorKey: String? = nil
    /// Opens the thread this message belongs to (or the parent, for a reply).
    var onOpenThread: (() -> Void)? = nil
    /// Interactions switch (`disableInteractions`): no menu and no chip taps.
    var interactionsDisabled: Bool = false
    /// Reactions and replies switches, from ChatConfig.
    var reactionsEnabled: Bool = true
    var reactionPickerEnabled: Bool = true
    var quickReactions: [String] = EmojiShortcodes.defaultQuickReactions
    var repliesEnabled: Bool = true
    var accentColor: Color = .blue
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.chatPalette) private var palette
    

    private var bubbleStyle: MessageBubbleStyle? { ConfigStore.shared.config.bubleMessage }

    @State private var showContextMenu = false
    @State private var showReactionPicker = false
    
    var body: some View {
        // System messages (`isSystemMessage="true"`) render as a centered pill, not a bubble.
        if message.isSystemMessage == "true" {
            return AnyView(SystemMessagePill(text: message.body))
        }

        if message.id == "delimiter-new" {
            return AnyView(
                UnreadMessagesDelimiter()
            )
        }

        if let callLog = message.callLog {
            return AnyView(CallLogRowView(callLog: callLog))
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
                
                if !inThread, let quote = quotedText {
                    Text(quote)
                        .font(.caption)
                        .foregroundColor(isUser ? .white.opacity(0.85) : .secondary)
                        .lineLimit(2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(isUser ? 0.15 : 0.05))
                        )
                        .overlay(
                            Rectangle()
                                .fill(accentColor)
                                .frame(width: 3),
                            alignment: isUser ? .trailing : .leading
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { onOpenThread?() }
                }

                if message.isDeleted == true {
                    Text("This message was deleted")
                        .font(.callout.italic())
                        .foregroundColor(.secondary)
                } else {
                    buildMediaOrTextContent()
                }

                if message.wasEdited == true, message.isDeleted != true {
                    Text("(edited)")
                        .font(.caption2)
                        .foregroundColor(isUser ? .white.opacity(0.7) : .secondary)
                }

                if !inThread, !threadReplies.isEmpty {
                    ThreadReplyPill(
                        replies: threadReplies,
                        isUser: isUser,
                        accentColor: accentColor,
                        onTap: { onOpenThread?() }
                    )
                }

                if message.isDeleted != true, reactionsEnabled {
                    ReactionChipsView(
                        reactions: message.reaction,
                        currentReactorKey: currentReactorKey,
                        accentColor: accentColor,
                        interactive: !interactionsDisabled,
                        onToggle: { emoji in onReactionTap?(emoji) }
                    )
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
                            receiptState: receiptState,
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
            // Reaction picker temporarily disabled.
            // .overlay(
            //     Group {
            //         if showReactionPicker {
            //             ReactionPickerView(
            //                 onReactionSelected: { emoji in
            //                     onReactionTap?(emoji)
            //                     showReactionPicker = false
            //                 },
            //                 onDismiss: {
            //                     showReactionPicker = false
            //                 }
            //             )
            //             .offset(y: -60)
            //         }
            //     },
            //     alignment: .top
            // )
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
                
                VStack(alignment: .leading, spacing: 6) {
                    if message.mediaAttachments.count > 1 {
                        AttachmentAlbumView(
                            attachments: message.mediaAttachments,
                            onTap: { index in
                                if let onAlbumTap {
                                    onAlbumTap(message, index)
                                } else {
                                    onMediaTap?(message)
                                }
                            }
                        )
                    } else {
                        MediaMessagePreview(
                            message: message,
                            mimeType: mimeType,
                            isUser: isUser,
                            onMediaTap: { mediaMessage in
                                onMediaTap?(mediaMessage)
                            }
                        )
                    }

                    // The caption typed with the files, shown under the media.
                    if let caption = message.caption, caption.contains(where: { !$0.isWhitespace }) {
                        Text(caption)
                            .font(.body)
                            .foregroundColor(messageTextColor)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(isUser ? .trailing : .leading)
                    }
                }
            } else {
                if message.body.lowercased() != "media" {
                    TranslatableMessageText(
                        message: message,
                        isUser: isUser,
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
                                        onReport: onReport,
                                        interactive: !interactionsDisabled && message.isDeleted != true,
                                        showReply: !inThread && repliesEnabled,
                                        showReactions: reactionsEnabled && message.isDeleted != true,
                                        showPicker: reactionPickerEnabled,
                                        quickReactions: quickReactions,
                                        onReact: { emoji in onReactionTap?(emoji) },
                                        onMoreReactions: { showReactionPicker = true }
                                    )
                                }
                                .onLongPressGesture {
                                    onLongPress?()
                                    // Reaction picker trigger temporarily disabled.
                                    // if onReactionTap != nil {
                                    //     showReactionPicker = true
                                    // }
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
                                        onReport: onReport,
                                        interactive: !interactionsDisabled && message.isDeleted != true,
                                        showReply: !inThread && repliesEnabled,
                                        showReactions: reactionsEnabled && message.isDeleted != true,
                                        showPicker: reactionPickerEnabled,
                                        quickReactions: quickReactions,
                                        onReact: { emoji in onReactionTap?(emoji) },
                                        onMoreReactions: { showReactionPicker = true }
                                    )
                                }
                                .onLongPressGesture {
                                    onLongPress?()
                                    // Reaction picker trigger temporarily disabled.
                                    // if onReactionTap != nil {
                                    //     showReactionPicker = true
                                    // }
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
            .sheet(isPresented: $showReactionPicker) {
                ReactionPickerSheet { emoji in
                    onReactionTap?(emoji)
                }
            }
        )
    }
    
    /// Quoted parent text for a message that answers another (web MessageReply).
    private var quotedText: String? {
        guard let parsed = ThreadReference.parse(message.mainMessage),
              parsed.id != nil,
              let text = parsed.text, !text.isEmpty else {
            return nil
        }
        return text
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
        if let own = ConfigStore.shared.config.colors?.ownMessageBackground, !own.isEmpty {
            return Color(hex: own)
        }
        // Dark: the palette's lifted primary keeps white text readable on a dark surface.
        if palette.isDark {
            return Color(hex: palette.primary)
        }
        if let primary = ConfigStore.shared.config.colors?.primary, !primary.isEmpty {
            return Color(hex: primary)
        }
        return Color.blue
    }
    
    private func incomingBubbleBackground() -> Color {
        if let configured = bubbleStyle?.backgroundMessage, !configured.isEmpty {
            return Color(hex: configured)
        }
        if let other = ConfigStore.shared.config.colors?.otherMessageBackground, !other.isEmpty {
            return Color(hex: other)
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
    var receiptState: ReceiptState = .sent
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
            } else {
                tick
            }
        }
    }

    /// Web tick rules: one check for sent, two for delivered, two in the accent
    /// colour once seen. Nothing for a pending or failed message.
    @ViewBuilder
    private var tick: some View {
        switch receiptState {
        case .none:
            EmptyView()
        case .sent:
            doubleCheck(count: 1, color: .white.opacity(0.7))
                .accessibilityLabel("Sent")
        case .delivered:
            doubleCheck(count: 2, color: .white.opacity(0.7))
                .accessibilityLabel("Delivered")
        case .seen:
            doubleCheck(count: 2, color: Color(red: 0.49, green: 0.70, blue: 1.0))
                .accessibilityLabel("Read")
        }
    }

    private func doubleCheck(count: Int, color: Color) -> some View {
        ZStack {
            Image(systemName: "checkmark")
                .font(.caption2)
                .foregroundColor(color)
                .offset(x: 0, y: 0)
            if count > 1 {
                Image(systemName: "checkmark")
                    .font(.caption2)
                    .foregroundColor(color)
                    .offset(x: 3, y: 0)
            }
        }
        .frame(width: 16, height: 12)
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
    /// False when the host turned interactions off: the menu is empty.
    var interactive: Bool = true
    /// "Reply" is hidden inside a thread and when `disableReplies` is set.
    var showReply: Bool = true
    /// Reaction row (quick shortcodes, plus the full picker when `showPicker`).
    var showReactions: Bool = false
    var showPicker: Bool = false
    var quickReactions: [String] = EmojiShortcodes.defaultQuickReactions
    var onReact: ((String) -> Void)? = nil
    var onMoreReactions: (() -> Void)? = nil
    
    private var isMediaMessage: Bool {
        let hasMediaFlag = message.isMediafile == "true"
        let hasLocation = message.location != nil && !(message.location ?? "").isEmpty
        return hasMediaFlag || hasLocation
    }

    var body: some View {
        Group {
            if interactive {
                if showReactions, let onReact = onReact {
                    ReactionQuickItems(
                        shortcodes: quickReactions,
                        showPicker: showPicker,
                        onSelect: onReact,
                        onMore: { onMoreReactions?() }
                    )
                }

                if showReply, let onReply = onReply {
                    Button(action: onReply) {
                        Label("Reply", systemImage: "arrowshape.turn.up.left")
                    }
                }

                if let onCopy = onCopy {
                    Button(action: onCopy) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }

                if isUser, !isMediaMessage, let onEdit = onEdit {
                    Button(action: onEdit) {
                        Label("Edit", systemImage: "pencil")
                    }
                }

                if isUser, let onDelete = onDelete, message.isDeleted != true {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }
}
