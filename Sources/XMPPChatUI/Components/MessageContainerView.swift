//
//  MessageContainerView.swift
//  XMPPChatUI
//
//  Advanced message container
//

import SwiftUI
import XMPPChatCore

public struct MessageContainerView: View {
    let message: Message
    let isUser: Bool
    let currentUserId: String
    let onReactionTap: ((String) -> Void)?
    let onMessageTap: (() -> Void)?
    let onLongPress: (() -> Void)?
    let customComponent: ((MessageProps) -> AnyView)?
    let colors: ChatColors?
    
    public init(
        message: Message,
        isUser: Bool,
        currentUserId: String,
        onReactionTap: ((String) -> Void)? = nil,
        onMessageTap: (() -> Void)? = nil,
        onLongPress: (() -> Void)? = nil,
        customComponent: ((MessageProps) -> AnyView)? = nil,
        colors: ChatColors? = nil
    ) {
        self.message = message
        self.isUser = isUser
        self.currentUserId = currentUserId
        self.onReactionTap = onReactionTap
        self.onMessageTap = onMessageTap
        self.onLongPress = onLongPress
        self.customComponent = customComponent
        self.colors = colors
    }
    
    public var body: some View {
        MessageBubble(
            message: message,
            isUser: isUser,
            isReply: false,
            currentUserId: currentUserId,
            onReactionTap: onReactionTap,
            onMessageTap: onMessageTap,
            onLongPress: onLongPress,
            customComponent: customComponent,
            colors: colors
        )
        .fadeIn(duration: 0.2)
        .scaleOnAppear(duration: 0.1)
    }
}
