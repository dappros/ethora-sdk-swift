//
//  UnreadMessagesIndicator.swift
//  XMPPChatUI
//
//  Unread messages indicator and navigation
//

import SwiftUI
import XMPPChatCore

public struct UnreadMessagesIndicator: View {
    let unreadCount: Int
    let onScrollToUnread: () -> Void
    
    public init(
        unreadCount: Int,
        onScrollToUnread: @escaping () -> Void
    ) {
        self.unreadCount = unreadCount
        self.onScrollToUnread = onScrollToUnread
    }
    
    public var body: some View {
        if unreadCount > 0 {
            Button(action: onScrollToUnread) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .font(.caption)
                    Text("\(unreadCount) new")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue)
                .cornerRadius(16)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
