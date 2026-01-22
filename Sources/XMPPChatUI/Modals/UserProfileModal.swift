//
//  UserProfileModal.swift
//  XMPPChatUI
//
//  User profile modal
//

import SwiftUI
import XMPPChatCore

public struct UserProfileModal: View {
    let user: User
    let isOwnProfile: Bool
    let onClose: () -> Void
    let onEdit: (() -> Void)?
    let onBlock: (() -> Void)?
    let onUnblock: (() -> Void)?
    let onSendMessage: (() -> Void)?
    
    @Environment(\.dismiss) var dismiss
    
    public init(
        user: User,
        isOwnProfile: Bool = false,
        onClose: @escaping () -> Void,
        onEdit: (() -> Void)? = nil,
        onBlock: (() -> Void)? = nil,
        onUnblock: (() -> Void)? = nil,
        onSendMessage: (() -> Void)? = nil
    ) {
        self.user = user
        self.isOwnProfile = isOwnProfile
        self.onClose = onClose
        self.onEdit = onEdit
        self.onBlock = onBlock
        self.onUnblock = onUnblock
        self.onSendMessage = onSendMessage
    }
    
    public var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Profile Image
                    if let imageURL = user.profileImage, let url = URL(string: imageURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 120, height: 120)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                                    )
                            case .failure(let error):
                                // Only log non-cancellation errors
                                let _ = {
                                    if let urlError = error as? URLError, urlError.code != .cancelled {
                                        // Log actual errors (not cancellations)
                                        //print("⚠️ Error loading profile image (non-cancellation): \(error.localizedDescription)")
                                    }
                                }()
                                // Always return initials view on failure
                                InitialsAvatarView(user: user)
                                    .frame(width: 120, height: 120)
                            case .empty:
                                InitialsAvatarView(user: user)
                                    .frame(width: 120, height: 120)
                            @unknown default:
                                InitialsAvatarView(user: user)
                                    .frame(width: 120, height: 120)
                            }
                        }
                    } else {
                        InitialsAvatarView(user: user)
                            .frame(width: 120, height: 120)
                    }
                    
                    // User Info
                    VStack(spacing: 8) {
                        Text(user.fullName)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        if let email = user.email {
                            Text(email)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        if let description = user.description, !description.isEmpty {
                            Text(description)
                                .font(.body)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        if isOwnProfile, let onEdit = onEdit {
                            Button(action: onEdit) {
                                Text("Edit Profile")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .cornerRadius(12)
                            }
                        } else {
                            if let onSendMessage = onSendMessage {
                                Button(action: onSendMessage) {
                                    Text("Send Message")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.blue)
                                        .cornerRadius(12)
                                }
                            }
                            
                            if let onBlock = onBlock {
                                Button(action: onBlock) {
                                    Text("Block User")
                                        .font(.headline)
                                        .foregroundColor(.red)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.red.opacity(0.1))
                                        .cornerRadius(12)
                                }
                            }
                            
                            if let onUnblock = onUnblock {
                                Button(action: onUnblock) {
                                    Text("Unblock User")
                                        .font(.headline)
                                        .foregroundColor(.blue)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(12)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding()
            }
            .navigationTitle(isOwnProfile ? "My Profile" : "Profile")
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
