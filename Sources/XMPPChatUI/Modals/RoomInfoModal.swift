//
//  RoomInfoModal.swift
//  XMPPChatUI
//
//  Room info modal
//

import SwiftUI
import XMPPChatCore

public struct RoomInfoModal: View {
    let room: Room
    let members: [User]
    let onClose: () -> Void
    let onEdit: (() -> Void)?
    let onLeave: (() -> Void)?
    let onDelete: (() -> Void)?
    
    @Environment(\.dismiss) var dismiss
    
    public init(
        room: Room,
        members: [User],
        onClose: @escaping () -> Void,
        onEdit: (() -> Void)? = nil,
        onLeave: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.room = room
        self.members = members
        self.onClose = onClose
        self.onEdit = onEdit
        self.onLeave = onLeave
        self.onDelete = onDelete
    }
    
    public var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Room Image
                    if let imageURL = room.roomBg, let url = URL(string: imageURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(height: 200)
                                    .cornerRadius(12)
                            case .failure(let error):
                                // Only log non-cancellation errors
                                let _ = {
                                    if let urlError = error as? URLError, urlError.code != .cancelled {
                                        // Log actual errors (not cancellations)
                                        //print("⚠️ Error loading room image (non-cancellation): \(error.localizedDescription)")
                                    }
                                }()
                                // Always return placeholder on failure
                                Rectangle()
                                    .fill(Color.blue.opacity(0.3))
                                    .frame(height: 200)
                                    .cornerRadius(12)
                            case .empty:
                                Rectangle()
                                    .fill(Color.blue.opacity(0.3))
                                    .frame(height: 200)
                                    .cornerRadius(12)
                            @unknown default:
                                Rectangle()
                                    .fill(Color.blue.opacity(0.3))
                                    .frame(height: 200)
                                    .cornerRadius(12)
                            }
                        }
                    }
                    
                    // Room Info
                    VStack(alignment: .leading, spacing: 8) {
                        Text(room.name ?? "Unnamed Room")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        if let description = room.description {
                            Text(description)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Label("\(members.count) members", systemImage: "person.2")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            if room.unreadMessages > 0 {
                                Label("\(room.unreadMessages) unread", systemImage: "envelope.badge")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // Members List
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Members")
                            .font(.headline)
                        
                        ForEach(members.prefix(10), id: \.id) { member in
                            HStack {
                                if let imageURL = member.profileImage, let url = URL(string: imageURL) {
                                    AsyncImage(url: url) { image in
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        InitialsAvatarView(user: member)
                                    }
                                    .frame(width: 40, height: 40)
                                    .clipShape(Circle())
                                } else {
                                    InitialsAvatarView(user: member)
                                        .frame(width: 40, height: 40)
                                }
                                
                                Text(member.fullName)
                                    .font(.subheadline)
                            }
                        }
                        
                        if members.count > 10 {
                            Text("+ \(members.count - 10) more")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Actions
                    VStack(spacing: 12) {
                        if let onEdit = onEdit {
                            Button(action: onEdit) {
                                Text("Edit Room")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .cornerRadius(12)
                            }
                        }
                        
                        if let onLeave = onLeave {
                            Button(action: onLeave) {
                                Text("Leave Room")
                                    .font(.headline)
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(12)
                            }
                        }
                        
                        if let onDelete = onDelete {
                            Button(role: .destructive, action: onDelete) {
                                Text("Delete Room")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.red)
                                    .cornerRadius(12)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Room Info")
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
