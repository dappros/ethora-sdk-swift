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
    let members: [RoomMember]
    let onClose: () -> Void
    let onEdit: (() -> Void)?
    let onLeave: (() -> Void)?
    let onDelete: (() -> Void)?
    
    @Environment(\.dismiss) var dismiss
    
    public init(
        room: Room,
        members: [RoomMember] = [],
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
    
    // Helper function to get full name from RoomMember
    private func getFullName(for member: RoomMember) -> String {
        if let firstName = member.firstName, let lastName = member.lastName {
            return "\(firstName) \(lastName)"
        } else if let firstName = member.firstName {
            return firstName
        } else if let lastName = member.lastName {
            return lastName
        } else if let name = member.name, !name.isEmpty {
            return name
        } else if let xmppUsername = member.xmppUsername {
            return xmppUsername
        }
        return "Unknown User"
    }
    
    // Helper function to get initials from RoomMember
    private func getInitials(for member: RoomMember) -> String {
        if let firstName = member.firstName, let lastName = member.lastName {
            let firstInitial = firstName.prefix(1).uppercased()
            let lastInitial = lastName.prefix(1).uppercased()
            return "\(firstInitial)\(lastInitial)"
        } else if let name = member.name, !name.isEmpty {
            let parts = name.components(separatedBy: " ")
            if parts.count > 1, let first = parts.first?.first, let last = parts.last?.first {
                return "\(first)\(last)".uppercased()
            } else if let first = name.first {
                return String(first).uppercased()
            }
        } else if let firstName = member.firstName, let first = firstName.first {
            return String(first).uppercased()
        } else if let lastName = member.lastName, let first = lastName.first {
            return String(first).uppercased()
        } else if let xmppUsername = member.xmppUsername, let first = xmppUsername.first {
            return String(first).uppercased()
        }
        return "?"
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
                    .padding(.leading, 16)
                    
                    // Members List
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Members")
                            .font(.headline)
                        
                        if members.isEmpty {
                            Text("No members")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(members, id: \.id) { member in
                                HStack(spacing: 12) {
                                    // Avatar
                                    Circle()
                                        .fill(Color.blue.opacity(0.3))
                                        .frame(width: 44, height: 44)
                                        .overlay(
                                            Text(getInitials(for: member))
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundColor(.blue)
                                        )
                                    
                                    // Full Name
                                    Text(getFullName(for: member))
                                        .font(.body)
                                    
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding(.leading, 16)
                    
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
