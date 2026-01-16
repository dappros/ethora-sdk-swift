//
//  UsersListView.swift
//  XMPPChatUI
//
//  Users list component
//

import SwiftUI
import XMPPChatCore

public struct UsersListView: View {
    let users: [User]
    let onUserSelected: ((User) -> Void)?
    let allowsSelection: Bool
    
    @State private var searchText: String = ""
    @State private var selectedUsers: Set<String> = []
    
    public init(
        users: [User],
        onUserSelected: ((User) -> Void)? = nil,
        allowsSelection: Bool = false
    ) {
        self.users = users
        self.onUserSelected = onUserSelected
        self.allowsSelection = allowsSelection
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            if !users.isEmpty {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search users...", text: $searchText)
                }
                .padding()
                #if os(iOS)
                .background(Color(uiColor: .systemGray6))
                #else
                .background(Color(NSColor.controlBackgroundColor))
                #endif
                .cornerRadius(8)
                .padding()
                
                // Users list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredUsers, id: \.id) { user in
                            UserRowView(
                                user: user,
                                isSelected: selectedUsers.contains(user.id),
                                allowsSelection: allowsSelection,
                                onTap: {
                                    if allowsSelection {
                                        if selectedUsers.contains(user.id) {
                                            selectedUsers.remove(user.id)
                                        } else {
                                            selectedUsers.insert(user.id)
                                        }
                                    } else {
                                        onUserSelected?(user)
                                    }
                                }
                            )
                        }
                    }
                }
            } else {
                VStack {
                    Image(systemName: "person.3")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No users found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
    }
    
    private var filteredUsers: [User] {
        if searchText.isEmpty {
            return users
        }
        let query = searchText.lowercased()
        return users.filter { user in
            user.fullName.lowercased().contains(query) ||
            user.email?.lowercased().contains(query) ?? false
        }
    }
    
    public func getSelectedUsers() -> [User] {
        return users.filter { selectedUsers.contains($0.id) }
    }
}
