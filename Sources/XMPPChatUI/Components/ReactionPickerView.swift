//
//  ReactionPickerView.swift
//  XMPPChatUI
//
//  Reaction picker component for emoji selection
//

import SwiftUI

public struct ReactionPickerView: View {
    let onReactionSelected: (String) -> Void
    let onDismiss: () -> Void
    
    @State private var selectedEmoji: String?
    
    // Common emoji reactions
    private let emojis = ["👍", "❤️", "😂", "😮", "😢", "🙏", "🔥", "👏"]
    
    public init(onReactionSelected: @escaping (String) -> Void, onDismiss: @escaping () -> Void) {
        self.onReactionSelected = onReactionSelected
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            ForEach(emojis, id: \.self) { emoji in
                Button(action: {
                    selectedEmoji = emoji
                    onReactionSelected(emoji)
                    onDismiss()
                }) {
                    Text(emoji)
                        .font(.title2)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(selectedEmoji == emoji ? Color.blue.opacity(0.2) : Color.clear)
                        )
                        .scaleEffect(selectedEmoji == emoji ? 1.2 : 1.0)
                        .animation(.spring(response: 0.3), value: selectedEmoji)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}
