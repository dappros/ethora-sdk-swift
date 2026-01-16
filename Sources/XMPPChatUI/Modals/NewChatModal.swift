//
//  NewChatModal.swift
//  XMPPChatUI
//
//  Create new chat modal
//

import SwiftUI
import XMPPChatCore

public struct NewChatModal: View {
    let availableUsers: [User]
    let onCreateChat: (String, String?, [User]) -> Void
    let onClose: () -> Void
    
    @State private var chatName: String = ""
    @State private var chatDescription: String = ""
    @State private var selectedUsers: Set<String> = []
    @State private var isGroupChat: Bool = false
    @State private var searchText: String = ""
    @Environment(\.dismiss) var dismiss
    
    public init(
        availableUsers: [User],
        onCreateChat: @escaping (String, String?, [User]) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.availableUsers = availableUsers
        self.onCreateChat = onCreateChat
        self.onClose = onClose
    }
    
    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Chat Type Toggle
                Picker("Chat Type", selection: $isGroupChat) {
                    Text("Private Chat").tag(false)
                    Text("Group Chat").tag(true)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Group Chat Name (if group)
                if isGroupChat {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Chat Name")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField("Enter chat name", text: $chatName)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description (Optional)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if #available(iOS 16.0, macOS 13.0, *) {
                            TextField("Enter description", text: $chatDescription, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(2...4)
                        } else {
                            TextField("Enter description", text: $chatDescription)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(4)
                        }
                    }
                    .padding(.horizontal)
                }
                
                // User Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text(isGroupChat ? "Select Members" : "Select User")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top)
                    
                    UserSearchView(
                        users: availableUsers,
                        allowsMultipleSelection: isGroupChat,
                        selectedUsers: $selectedUsers
                    )
                }
                
                // Create Button
                Button(action: {
                    let users = availableUsers.filter { selectedUsers.contains($0.id) }
                    if isGroupChat {
                        onCreateChat(chatName, chatDescription.isEmpty ? nil : chatDescription, users)
                    } else if let firstUser = users.first {
                        onCreateChat("", nil, [firstUser])
                    }
                    dismiss()
                }) {
                    Text(isGroupChat ? "Create Group Chat" : "Start Chat")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canCreate ? Color.blue : Color.gray)
                        .cornerRadius(12)
                }
                .disabled(!canCreate)
                .padding()
            }
            .navigationTitle("New Chat")
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
    
    private var canCreate: Bool {
        if isGroupChat {
            return !chatName.isEmpty && !selectedUsers.isEmpty
        } else {
            return selectedUsers.count == 1
        }
    }
}
