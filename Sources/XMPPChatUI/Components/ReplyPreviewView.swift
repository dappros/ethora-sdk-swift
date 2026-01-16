//
//  ReplyPreviewView.swift
//  XMPPChatUI
//
//  Reply preview component
//

import SwiftUI
import XMPPChatCore

struct ReplyPreviewView: View {
    let mainMessage: String // This should be message ID or message data
    
    var body: some View {
        // Placeholder - should load and display the main message
        HStack {
            Rectangle()
                .fill(Color.blue)
                .frame(width: 4)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Replying to message")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(mainMessage)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}
