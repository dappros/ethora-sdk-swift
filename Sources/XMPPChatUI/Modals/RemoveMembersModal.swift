//
//  RemoveMembersModal.swift
//  XMPPChatUI
//
//  Remove members from room modal
//

import SwiftUI
import XMPPChatCore

public struct RemoveMembersModal: View {
    let room: Room
    let members: [User]
    let onRemoveMembers: ([User]) -> Void
    let onClose: () -> Void
    
    @State private var selectedUsers: Set<String> = []
    @State private var searchText: String = ""
    @Environment(\.dismiss) var dismiss
    
    public init(
        room: Room,
        members: [User],
        onRemoveMembers: @escaping ([User]) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.room = room
        self.members = members
        self.onRemoveMembers = onRemoveMembers
        self.onClose = onClose
    }
    
    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                UserSearchView(
                    users: filteredMembers,
                    allowsMultipleSelection: true
                )
                
                if !selectedUsers.isEmpty {
                    Button(action: {
                        let usersToRemove = members.filter { selectedUsers.contains($0.id) }
                        onRemoveMembers(usersToRemove)
                        dismiss()
                    }) {
                        Text("Remove \(selectedUsers.count) member(s)")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .cornerRadius(12)
                    }
                    .padding()
                }
            }
            .navigationTitle("Remove Members")
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
    
    private var filteredMembers: [User] {
        if searchText.isEmpty {
            return members
        }
        let query = searchText.lowercased()
        return members.filter { user in
            user.fullName.lowercased().contains(query) ||
            user.email?.lowercased().contains(query) ?? false
        }
    }
}
