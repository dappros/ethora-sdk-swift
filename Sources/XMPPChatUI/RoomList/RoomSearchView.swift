//
//  RoomSearchView.swift
//  XMPPChatUI
//
//  Room search and filter component
//

import SwiftUI
import XMPPChatCore

public struct RoomSearchView: View {
    let rooms: [Room]
    let onRoomSelected: (Room) -> Void
    
    @State private var searchText: String = ""
    @State private var sortOption: RoomSortOption = .date
    @FocusState private var isSearchFocused: Bool
    
    public init(
        rooms: [Room],
        onRoomSelected: @escaping (Room) -> Void
    ) {
        self.rooms = rooms
        self.onRoomSelected = onRoomSelected
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Search Input
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search rooms...", text: $searchText)
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
            
            // Sort Options
            HStack {
                Text("Sort by:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Sort", selection: $sortOption) {
                    ForEach(RoomSortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            
            // Filtered and Sorted Rooms
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredAndSortedRooms, id: \.jid) { room in
                        RoomRowView(room: room, onTap: {
                            onRoomSelected(room)
                        })
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
    
    private var filteredAndSortedRooms: [Room] {
        var filtered = rooms
        
        // Filter by search text
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            filtered = filtered.filter { room in
                (room.name.lowercased().contains(query) ?? false) ||
                (room.description?.lowercased().contains(query) ?? false)
            }
        }
        
        // Sort
        switch sortOption {
        case .date:
            filtered.sort { ($0.lastMessage?.date ?? Date.distantPast) > ($1.lastMessage?.date ?? Date.distantPast) }
        case .name:
            filtered.sort { ($0.name ?? "") < ($1.name ?? "") }
        case .unread:
            filtered.sort { ($0.unreadMessages ?? 0) > ($1.unreadMessages ?? 0) }
        }
        
        return filtered
    }
}

enum RoomSortOption: String, CaseIterable {
    case date = "date"
    case name = "name"
    case unread = "unread"
    
    var displayName: String {
        switch self {
        case .date: return "Date"
        case .name: return "Name"
        case .unread: return "Unread"
        }
    }
}

struct RoomRowView: View {
    let room: Room
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Room Avatar
            if let imageURL = room.roomBg, let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.blue.opacity(0.3))
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text((room.name ?? "R").prefix(1).uppercased())
                            .font(.headline)
                            .foregroundColor(.blue)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(room.name ?? "Unnamed Room")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    if room.unreadMessages > 0 {
                        Text("\(room.unreadMessages)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                }
                
                if let lastMessage = room.lastMessage {
                    Text(lastMessage.body)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                if let date = room.lastMessage?.date {
                    Text(formatDate(date))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }
}
