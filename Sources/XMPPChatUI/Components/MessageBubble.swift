//
//  MessageBubble.swift
//  XMPPChatUI
//
//  Message bubble component with avatar, reactions, reply preview
//

import SwiftUI

public struct MessageBubble: View {
    let message: Message
    let isUser: Bool
    let isReply: Bool
    let currentUserId: String
    let onReactionTap: ((String) -> Void)?
    let onMessageTap: (() -> Void)?
    let onLongPress: (() -> Void)?
    let customComponent: ((MessageProps) -> AnyView)?
    let colors: ChatColors?
    
    @State private var showReactionPicker = false
    @State private var showMessageMenu = false
    
    public init(
        message: Message,
        isUser: Bool,
        isReply: Bool = false,
        currentUserId: String,
        onReactionTap: ((String) -> Void)? = nil,
        onMessageTap: (() -> Void)? = nil,
        onLongPress: (() -> Void)? = nil,
        customComponent: ((MessageProps) -> AnyView)? = nil,
        colors: ChatColors? = nil
    ) {
        self.message = message
        self.isUser = isUser
        self.isReply = isReply
        self.currentUserId = currentUserId
        self.onReactionTap = onReactionTap
        self.onMessageTap = onMessageTap
        self.onLongPress = onLongPress
        self.customComponent = customComponent
        self.colors = colors
    }
    
    public var body: some View {
        if let customComponent = customComponent {
            customComponent(MessageProps(message: message, isUser: isUser, isReply: isReply))
        } else {
            DefaultMessageBubble(
                message: message,
                isUser: isUser,
                isReply: isReply,
                currentUserId: currentUserId,
                onReactionTap: onReactionTap,
                onMessageTap: onMessageTap,
                onLongPress: onLongPress,
                colors: colors
            )
        }
    }
}

struct DefaultMessageBubble: View {
    let message: Message
    let isUser: Bool
    let isReply: Bool
    let currentUserId: String
    let onReactionTap: ((String) -> Void)?
    let onMessageTap: (() -> Void)?
    let onLongPress: (() -> Void)?
    let colors: ChatColors?
    
    @State private var showReactionPicker = false
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !isUser {
                AvatarView(user: message.user)
            }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if !isUser {
                    Text(message.user.fullName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Reply preview
                if let mainMessage = message.mainMessage, isReply {
                    ReplyPreviewView(mainMessage: mainMessage)
                }
                
                // Message content
                if message.isDeleted == true {
                    DeletedMessageView()
                } else if message.isMediafile != nil || message.mimetype != nil {
                    MediaMessageView(message: message, isUser: isUser)
                } else {
                    Text(message.body)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(isUser ? (colors?.primaryColor ?? Color.blue) : Color.gray.opacity(0.2))
                        )
                        .foregroundColor(isUser ? .white : .primary)
                }
                
                // Reactions
                if let reactions = message.reaction, !reactions.isEmpty {
                    ReactionBadgesView(reactions: reactions)
                }
                
                // Timestamp
                Text(formatTimestamp(message.date))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if isUser {
                AvatarView(user: message.user)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onMessageTap?()
        }
        .onLongPressGesture {
            onLongPress?()
            HapticFeedback.buttonPress()
        }
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
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct AvatarView: View {
    let user: User
    
    var body: some View {
        Group {
            if let profileImage = user.profileImage, let url = URL(string: profileImage) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    InitialsAvatarView(user: user)
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
            } else {
                InitialsAvatarView(user: user)
            }
        }
    }
}

struct InitialsAvatarView: View {
    let user: User
    
    var body: some View {
        Circle()
            .fill(Color.blue.opacity(0.3))
            .frame(width: 32, height: 32)
            .overlay(
                Text(getInitials(for: user))
                    .font(.caption)
                    .foregroundColor(.blue)
            )
    }
    
    private func getInitials(for user: User) -> String {
        if let firstName = user.firstName, let lastName = user.lastName {
            return "\(firstName.prefix(1))\(lastName.prefix(1))".uppercased()
        } else if let name = user.name {
            let parts = name.components(separatedBy: " ")
            if parts.count > 1, let first = parts.first?.first, let last = parts.last?.first {
                return "\(first)\(last)".uppercased()
            } else if let first = name.first {
                return String(first).uppercased()
            }
        }
        return "?"
    }
}

struct ReplyPreviewView: View {
    let mainMessage: String
    
    var body: some View {
        HStack {
            Rectangle()
                .fill(Color.blue)
                .frame(width: 3)
            
            Text(mainMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

struct ReactionBadgesView: View {
    let reactions: [String: ReactionMessage]
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(reactions.values), id: \.emoji.joined()) { reaction in
                HStack(spacing: 2) {
                    ForEach(reaction.emoji, id: \.self) { emoji in
                        Text(emoji)
                            .font(.caption)
                    }
                    Text("\(reaction.data.count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(12)
            }
        }
    }
}

struct DeletedMessageView: View {
    var body: some View {
        HStack {
            Image(systemName: "trash")
                .font(.caption)
            Text("This message was deleted")
                .font(.caption)
                .italic()
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
