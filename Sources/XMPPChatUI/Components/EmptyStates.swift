//
//  EmptyStates.swift
//  XMPPChatUI
//
//  Empty state views
//

import SwiftUI

public struct NoMessagesPlaceholder: View {
    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "message")
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("No messages yet")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Start the conversation!")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

public struct NoRoomsPlaceholder: View {
    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("No rooms yet")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Create a new chat to get started")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

public struct ConnectionErrorState: View {
    let message: String
    let onRetry: (() -> Void)?
    
    public init(message: String = "Connection error", onRetry: (() -> Void)? = nil) {
        self.message = message
        self.onRetry = onRetry
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text(message)
                .font(.headline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
            
            if let onRetry = onRetry {
                Button("Retry") {
                    onRetry()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
