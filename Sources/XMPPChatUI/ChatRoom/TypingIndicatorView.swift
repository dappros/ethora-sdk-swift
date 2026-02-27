//
//  TypingIndicatorView.swift
//  XMPPChatUI
//

import SwiftUI

struct TypingIndicatorView: View {
    let users: [String]
    @State private var animatingDots: Int = 0
    
    var body: some View {
        HStack(spacing: 4) {
            Text(typingText)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading)
            
            // Animated dots
            HStack(spacing: 2) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 4, height: 4)
                        .opacity(animatingDots == index ? 1.0 : 0.3)
                        .animation(
                            Animation.easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.2),
                            value: animatingDots
                        )
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .background(chatIncomingBubbleBackground().opacity(0.8))
        .cornerRadius(8)
        .padding(.horizontal)
        .onAppear {
            // Cycle through dots
            Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
                withAnimation {
                    animatingDots = (animatingDots + 1) % 3
                }
            }
        }
    }
    
    private var typingText: String {
        if users.isEmpty {
            return "Someone is typing"
        } else if users.count == 1 {
            return "\(users[0]) is typing"
        } else if users.count == 2 {
            return "\(users[0]) and \(users[1]) are typing"
        } else {
            return "\(users.count) people are typing"
        }
    }
}
