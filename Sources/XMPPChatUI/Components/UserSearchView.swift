//
//  UserSearchView.swift
//  XMPPChatUI
//
//  User search and filter component
//

import SwiftUI
import XMPPChatCore

public struct UserSearchView: View {
    let users: [User]
    let onUserSelected: ((User) -> Void)?
    let allowsMultipleSelection: Bool
    
    @State private var searchText: String = ""
    @Binding var selectedUsers: Set<String>
    @FocusState private var isSearchFocused: Bool
    
    public init(
        users: [User],
        onUserSelected: ((User) -> Void)? = nil,
        allowsMultipleSelection: Bool = false,
        selectedUsers: Binding<Set<String>>? = nil
    ) {
        self.users = users
        self.onUserSelected = onUserSelected
        self.allowsMultipleSelection = allowsMultipleSelection
        self._selectedUsers = selectedUsers ?? Binding(
            get: { [] },
            set: { _ in }
        )
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Search Input
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search users...", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            #if os(iOS)
            .background(Color(uiColor: .systemGray6))
            #else
            .background(Color(NSColor.controlBackgroundColor))
            #endif
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            // Selected Users Count (if multiple selection)
            if allowsMultipleSelection && !selectedUsers.isEmpty {
                HStack {
                    Text("\(selectedUsers.count) selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Clear") {
                        selectedUsers.removeAll()
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            
            // Filtered Users List
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredUsers, id: \.id) { user in
                        UserRowView(
                            user: user,
                            isSelected: selectedUsers.contains(user.id),
                            allowsSelection: allowsMultipleSelection,
                            onTap: {
                                if allowsMultipleSelection {
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
        }
                            #if os(iOS)
                            .background(Color(uiColor: .systemBackground))
                            #else
                            .background(Color(NSColor.controlBackgroundColor))
                            #endif
    }
    
    private var filteredUsers: [User] {
        if searchText.isEmpty {
            return users
        }
        
        let query = searchText.lowercased()
        return users.filter { user in
            (user.firstName?.lowercased().contains(query) ?? false) ||
            (user.lastName?.lowercased().contains(query) ?? false) ||
            (user.email?.lowercased().contains(query) ?? false) ||
            (user.fullName.lowercased().contains(query))
        }
    }
    
    public func getSelectedUsers() -> [User] {
        return users.filter { selectedUsers.contains($0.id) }
    }
}

struct UserRowView: View {
    let user: User
    let isSelected: Bool
    let allowsSelection: Bool
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // User Avatar
            if let imageURL = user.profileImage, let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                    case .failure(let error):
                        // Only log non-cancellation errors
                        let _ = {
                            if let urlError = error as? URLError, urlError.code != .cancelled {
                                // Log actual errors (not cancellations)
                                print("⚠️ Error loading user avatar (non-cancellation): \(error.localizedDescription)")
                            }
                        }()
                        // Always return initials view on failure
                        InitialsAvatarView(user: user)
                            .frame(width: 44, height: 44)
                    case .empty:
                        InitialsAvatarView(user: user)
                            .frame(width: 44, height: 44)
                    @unknown default:
                        InitialsAvatarView(user: user)
                            .frame(width: 44, height: 44)
                    }
                }
            } else {
                InitialsAvatarView(user: user)
                    .frame(width: 44, height: 44)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(user.fullName)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                if let email = user.email {
                    Text(email)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if allowsSelection {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .gray)
                    .font(.title3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}
