//
//  ChatHeaderView.swift
//  XMPPChatUI
//

import SwiftUI
import XMPPChatCore

struct ChatHeaderView: View {
    let room: Room
    let isTyping: Bool
    let composingUsers: [String]
    let messages: [Message]
    let currentUserId: String
    let currentUserXmppUsername: String?
    let onBack: () -> Void
    let onInfo: (() -> Void)?
    
    init(
        room: Room,
        isTyping: Bool = false,
        composingUsers: [String] = [],
        messages: [Message] = [],
        currentUserId: String = "",
        currentUserXmppUsername: String? = nil,
        onBack: @escaping () -> Void,
        onInfo: (() -> Void)? = nil
    ) {
        self.room = room
        self.isTyping = isTyping
        self.composingUsers = composingUsers
        self.messages = messages
        self.currentUserId = currentUserId
        self.currentUserXmppUsername = currentUserXmppUsername
        self.onBack = onBack
        self.onInfo = onInfo
    }
    
    // Get user names from composing user IDs
    private var typingUserNames: [String] {
        // Filter out current user
        let filteredUsers = composingUsers.filter { userId in
            let normalizedUserId = userId.lowercased().trimmingCharacters(in: .whitespaces)
            let normalizedCurrentId = currentUserId.lowercased().trimmingCharacters(in: .whitespaces)
            
            if let currentXmpp = currentUserXmppUsername {
                let normalizedCurrentXmpp = currentXmpp.lowercased().trimmingCharacters(in: .whitespaces)
                let normalizedUserXmpp = userId.lowercased().trimmingCharacters(in: .whitespaces)
                if normalizedUserXmpp == normalizedCurrentXmpp {
                    return false
                }
            }
            
            return normalizedUserId != normalizedCurrentId
        }
        
        // Get user names from room.members first, then from messages as fallback
        return filteredUsers.compactMap { userId in
            // First try to find in room.members
            if let members = room.members {
                if let member = members.first(where: { member in
                    let normalizedMemberId = member.id.lowercased().trimmingCharacters(in: .whitespaces)
                    let normalizedMemberXmpp = member.xmppUsername?.lowercased().trimmingCharacters(in: .whitespaces) ?? ""
                    let normalizedUserId = userId.lowercased().trimmingCharacters(in: .whitespaces)
                    
                    return normalizedMemberId == normalizedUserId || 
                           normalizedMemberXmpp == normalizedUserId ||
                           member.jid?.lowercased() == normalizedUserId
                }) {
                    // Use name, or firstName + lastName, or firstName, or lastName, or xmppUsername as fallback
                    if let name = member.name, !name.isEmpty {
                        return name
                    } else if let firstName = member.firstName, let lastName = member.lastName {
                        return "\(firstName) \(lastName)"
                    } else if let firstName = member.firstName {
                        return firstName
                    } else if let lastName = member.lastName {
                        return lastName
                    } else if let xmppUsername = member.xmppUsername {
                        return xmppUsername
                    }
                }
            }
            
            // Fallback: try to find user in messages
            if let message = messages.first(where: { 
                $0.user.id == userId || 
                $0.user.xmppUsername?.lowercased() == userId.lowercased() ||
                $0.user.xmppUsername?.lowercased() == userId.lowercased().components(separatedBy: "@").first
            }) {
                return message.user.fullName
            }
            
            // Last fallback: return userId (shouldn't happen normally)
            return userId
        }
    }
    
    private var typingText: String {
        let names = typingUserNames
        if names.isEmpty {
            return "\(room.usersCnt) members"
        } else if names.count == 1 {
            return "\(names[0]) is typing"
        } else if names.count == 2 {
            return "\(names[0]) and \(names[1]) are typing"
        } else {
            return "\(names[0]) and \(names.count - 1) others are typing"
        }
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
            
            Spacer()
            
            VStack(alignment: .center, spacing: 4) {
                Text(room.title)
                    .font(.headline)
                
                if isTyping && !typingUserNames.isEmpty {
                    HStack(spacing: 2) {
                        Text(typingText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HeaderTypingDotsView()
                    }
                } else {
                    Text(typingText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(chatSeparatorColor())
                .frame(height: onePixel())
        }
        .shadow(radius: 1)
    }
}

// MARK: - Typing Dots Animation for Header
struct HeaderTypingDotsView: View {
    @State private var dotIndex: Int = 0
    @State private var isVisible: Bool = true
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 4, height: 4)
                    .opacity(shouldShowDot(index) ? 1.0 : 0.3)
            }
        }
        .onAppear {
            startAnimation()
        }
    }
    
    private func shouldShowDot(_ index: Int) -> Bool {
        if !isVisible {
            return false
        }
        return index <= dotIndex
    }
    
    private func startAnimation() {
        Task {
            while true {
                // Show dots one by one
                for i in 0..<3 {
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            dotIndex = i
                            isVisible = true
                        }
                    }
                    try? await Task.sleep(nanoseconds: 400_000_000) // 0.4 seconds
                }
                
                // Hide all dots
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isVisible = false
                        dotIndex = 0
                    }
                }
                try? await Task.sleep(nanoseconds: 400_000_000) // 0.4 seconds pause before restart
            }
        }
    }
}

// Helper functions (copies from original file)
private func chatSeparatorColor() -> Color {
    #if os(iOS)
    return Color(uiColor: .separator)
    #else
    return Color(NSColor.separatorColor)
    #endif
}

private func onePixel() -> CGFloat {
    #if os(iOS)
    return 1.0 / UIScreen.main.scale
    #else
    return 1.0
    #endif
}
