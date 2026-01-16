//
//  TypingIndicatorView.swift
//  XMPPChatUI
//
//  Typing indicator component
//

import SwiftUI
import XMPPChatCore

public struct ConfigurableTypingIndicatorView: View {
    let usersTyping: [String]
    let text: String
    let isVisible: Bool
    let position: TypingIndicatorPosition
    let customComponent: ((TypingIndicatorProps) -> AnyView)?
    
    public init(
        usersTyping: [String],
        text: String,
        isVisible: Bool,
        position: TypingIndicatorPosition = .bottom,
        customComponent: ((TypingIndicatorProps) -> AnyView)? = nil
    ) {
        self.usersTyping = usersTyping
        self.text = text
        self.isVisible = isVisible
        self.position = position
        self.customComponent = customComponent
    }
    
    public var body: some View {
        if let customComponent = customComponent {
            customComponent(TypingIndicatorProps(
                usersTyping: usersTyping,
                text: text,
                isVisible: isVisible
            ))
        } else {
            DefaultTypingIndicatorView(
                usersTyping: usersTyping,
                text: text,
                isVisible: isVisible,
                position: position
            )
        }
    }
}

public struct TypingIndicatorProps {
    public let usersTyping: [String]
    public let text: String
    public let isVisible: Bool
    
    public init(usersTyping: [String], text: String, isVisible: Bool) {
        self.usersTyping = usersTyping
        self.text = text
        self.isVisible = isVisible
    }
}

struct DefaultTypingIndicatorView: View {
    let usersTyping: [String]
    let text: String
    let isVisible: Bool
    let position: TypingIndicatorPosition
    
    var body: some View {
        if isVisible && !usersTyping.isEmpty {
            HStack(spacing: 8) {
                TypingDotsView()
                
                Text(text)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(16)
            .transition(.opacity.combined(with: .scale))
            .animation(.easeInOut, value: isVisible)
        }
    }
}

struct TypingDotsView: View {
    @State private var animating = false
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .scaleEffect(animating ? 1.2 : 0.8)
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: animating
                    )
            }
        }
        .onAppear {
            animating = true
        }
    }
}
