//
//  BlockedUsersModal.swift
//  XMPPChatUI
//
//  Blocked users modal
//

import SwiftUI
import XMPPChatCore

public struct BlockedUsersModal: View {
    let blockedUsers: [User]
    let onUnblock: (User) -> Void
    let onClose: () -> Void
    
    @Environment(\.dismiss) var dismiss
    
    public init(
        blockedUsers: [User],
        onUnblock: @escaping (User) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.blockedUsers = blockedUsers
        self.onUnblock = onUnblock
        self.onClose = onClose
    }
    
    public var body: some View {
        NavigationView {
            List {
                if blockedUsers.isEmpty {
                    VStack {
                        Image(systemName: "person.crop.circle.badge.xmark")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No blocked users")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else {
                    ForEach(blockedUsers, id: \.id) { user in
                        HStack {
                            if let imageURL = user.profileImage, let url = URL(string: imageURL) {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    InitialsAvatarView(user: user)
                                }
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                            } else {
                                InitialsAvatarView(user: user)
                                    .frame(width: 44, height: 44)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.fullName)
                                    .font(.headline)
                                if let email = user.email {
                                    Text(email)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                onUnblock(user)
                            }) {
                                Text("Unblock")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Blocked Users")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}
