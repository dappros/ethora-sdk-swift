//
//  AddMembersModal.swift
//  XMPPChatUI
//
//  Add members to room modal
//

import SwiftUI
import XMPPChatCore

public struct AddMembersModal: View {
    let room: Room
    let availableUsers: [User]
    let onAddMembers: ([User]) -> Void
    let onClose: () -> Void
    
    @State private var selectedUsers: Set<String> = []
    @State private var searchText: String = ""
    @Environment(\.dismiss) var dismiss
    
    public init(
        room: Room,
        availableUsers: [User],
        onAddMembers: @escaping ([User]) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.room = room
        self.availableUsers = availableUsers
        self.onAddMembers = onAddMembers
        self.onClose = onClose
    }
    
    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                UserSearchView(
                    users: filteredUsers,
                    allowsMultipleSelection: true
                )
                .onAppear {
                    // Get selected users when view appears
                }
                
                // Add Button
                if !selectedUsers.isEmpty {
                    Button(action: {
                        let usersToAdd = availableUsers.filter { selectedUsers.contains($0.id) }
                        onAddMembers(usersToAdd)
                        dismiss()
                    }) {
                        Text("Add \(selectedUsers.count) member(s)")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .padding()
                }
            }
            .navigationTitle("Add Members")
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
    
    private var filteredUsers: [User] {
        if searchText.isEmpty {
            return availableUsers
        }
        let query = searchText.lowercased()
        return availableUsers.filter { user in
            user.fullName.lowercased().contains(query) ||
            user.email?.lowercased().contains(query) ?? false
        }
    }
}
