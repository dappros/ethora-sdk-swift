//
//  MessageBubble.swift
//  XMPPChatUI
//
//  Message bubble component with avatar, reactions, reply preview
//

import SwiftUI
import XMPPChatCore

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
                    VStack(alignment: .leading, spacing: 8) {
                        UniversalMarkdownTextView(
                            text: message.body,
                            foregroundColor: isUser ? .white : .primary
                        )
                        
                        // URL Previews
                        let urls = message.body.extractURLs()
                        if !urls.isEmpty {
                            ForEach(urls, id: \.self) { url in
                                URLPreviewCard(url: url, isUserMessage: isUser)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isUser ? 
                                  (colors?.primary != nil ? hexColor(colors!.primary) : Color(red: 0.0, green: 0.32, blue: 0.80)) : 
                                  Color(red: 0.95, green: 0.97, blue: 0.99))
                    )
                    .foregroundColor(isUser ? .white : .primary)
                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                    
                    // Translations
                    MessageTranslationsView(
                        message: message,
                        isUser: isUser,
                        langSource: "en", // Should come from config
                        config: nil // Should pass config
                    )
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
        .fadeIn(duration: 0.2)
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
    
    private func hexColor(_ hex: String) -> Color {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        return Color(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct AvatarView: View {
    let user: User
    
    var body: some View {
        Group {
            if let profileImage = user.profileImage, let url = URL(string: profileImage) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                    case .failure(let error):
                        // Only log non-cancellation errors
                        let _ = {
                            if let urlError = error as? URLError, urlError.code != .cancelled {
                                // Log actual errors (not cancellations)
                                print("⚠️ Error loading avatar (non-cancellation): \(error.localizedDescription)")
                            }
                        }()
                        // Always return initials view on failure
                        InitialsAvatarView(user: user)
                    case .empty:
                        InitialsAvatarView(user: user)
                    @unknown default:
                        InitialsAvatarView(user: user)
                    }
                }
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

struct ReactionBadgesView: View {
    let reactions: [String: ReactionMessage]
    
    private var reactionItems: [(id: String, reaction: ReactionMessage)] {
        reactions.values.map { reaction in
            (id: reaction.emoji.joined(separator: ""), reaction: reaction)
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(reactionItems, id: \.id) { item in
                HStack(spacing: 2) {
                    ForEach(item.reaction.emoji, id: \.self) { emoji in
                        Text(emoji)
                            .font(.caption)
                    }
                    Text("\(item.reaction.data.count)")
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
