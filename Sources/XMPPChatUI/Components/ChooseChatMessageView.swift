//
//  ChooseChatMessageView.swift
//  XMPPChatUI
//
//  Message selection UI
//

import SwiftUI
import XMPPChatCore

public struct ChooseChatMessageView: View {
    let messages: [Message]
    let onMessageSelected: (Message) -> Void
    let onClose: () -> Void
    
    @State private var searchText: String = ""
    @Environment(\.dismiss) var dismiss
    
    public init(
        messages: [Message],
        onMessageSelected: @escaping (Message) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.messages = messages
        self.onMessageSelected = onMessageSelected
        self.onClose = onClose
    }
    
    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search messages...", text: $searchText)
                }
                .padding()
                #if os(iOS)
                .background(Color(uiColor: .systemGray6))
                #else
                .background(Color(NSColor.controlBackgroundColor))
                #endif
                .cornerRadius(8)
                .padding()
                
                // Messages list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredMessages, id: \.id) { message in
                            MessageSelectionRow(
                                message: message,
                                onTap: {
                                    onMessageSelected(message)
                                    dismiss()
                                }
                            )
                        }
                    }
                }
            }
            .navigationTitle("Select Message")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var filteredMessages: [Message] {
        if searchText.isEmpty {
            return messages
        }
        let query = searchText.lowercased()
        return messages.filter { $0.body.lowercased().contains(query) }
    }
}

struct MessageSelectionRow: View {
    let message: Message
    let onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(message.user.fullName)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text(formatDate(message.date))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(message.body)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineLimit(2)
        }
        .padding()
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
