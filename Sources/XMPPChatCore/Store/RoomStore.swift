//
//  RoomStore.swift
//  XMPPChatCore
//
//  Room state management (Redux-like) for SwiftUI
//

import Foundation
import Combine

@MainActor
public class RoomStore: ObservableObject {
    public static let shared = RoomStore()
    
    // MARK: - Published Properties
    
    @Published public var rooms: [String: Room] = [:]
    @Published public var activeRoomJID: String?
    @Published public var isLoading: Bool = false
    @Published public var globalLoading: Bool = false
    
    // Edit action state
    @Published public var editAction: EditAction?
    
    // Users set (for quick lookup)
    @Published public var usersSet: [String: RoomMember] = [:]
    
    // Report room state
    @Published public var reportRoom: ReportRoomState = ReportRoomState()
    
    // Loading text
    @Published public var loadingText: String?
    
    // MARK: - Initialization
    
    private init() {
        loadFromCache()
    }
    
    // MARK: - Room Management
    
    /// Add or update a room
    public func addRoom(_ room: Room) {
        rooms[room.jid] = room
        saveToCache()
    }
    
    /// Add room from API
    public func addRoomFromApi(_ room: Room) {
        addRoom(room)
    }
    
    /// Delete a room
    public func deleteRoom(jid: String) {
        rooms.removeValue(forKey: jid)
        if activeRoomJID == jid {
            activeRoomJID = nil
        }
        saveToCache()
    }
    
    /// Update room
    public func updateRoom(jid: String, updates: PartialRoomUpdate) {
        guard var room = rooms[jid] else { return }
        
        if let usersCnt = updates.usersCnt {
            room.usersCnt = usersCnt
        }
        if let messages = updates.messages {
            room.messages = messages
        }
        if let isLoading = updates.isLoading {
            room.isLoading = isLoading
        }
        if let roomBg = updates.roomBg {
            room.roomBg = roomBg
        }
        if let members = updates.members {
            room.members = members
        }
        if let type = updates.type {
            room.type = type
        }
        if let description = updates.description {
            room.description = description
        }
        if let picture = updates.picture {
            room.picture = picture
        }
        if let lastMessage = updates.lastMessage {
            room.lastMessage = lastMessage
        }
        if let lastMessageTimestamp = updates.lastMessageTimestamp {
            room.lastMessageTimestamp = lastMessageTimestamp
        }
        if let icon = updates.icon {
            room.icon = icon
        }
        if let composing = updates.composing {
            room.composing = composing
        }
        if let composingList = updates.composingList {
            room.composingList = composingList
        }
        if let lastViewedTimestamp = updates.lastViewedTimestamp {
            room.lastViewedTimestamp = lastViewedTimestamp
        }
        if let unreadMessages = updates.unreadMessages {
            room.unreadMessages = unreadMessages
        }
        if let noMessages = updates.noMessages {
            room.noMessages = noMessages
        }
        if let role = updates.role {
            room.role = role
        }
        if let messageStats = updates.messageStats {
            room.messageStats = messageStats
        }
        if let historyComplete = updates.historyComplete {
            room.historyComplete = historyComplete
        }
        
        rooms[jid] = room
        saveToCache()
    }
    
    /// Set active room
    public func setActiveRoom(_ jid: String?) {
        activeRoomJID = jid
        saveToCache()
    }
    
    /// Get active room
    public func getActiveRoom() -> Room? {
        guard let jid = activeRoomJID else { return nil }
        return rooms[jid]
    }
    
    // MARK: - Message Management
    
    /// Add message to room
    public func addMessage(_ message: Message, toRoomJID roomJID: String) {
        guard var room = rooms[roomJID] else { return }
        
        // Check if message already exists
        if room.messages.contains(where: { $0.id == message.id }) {
            return
        }
        
        room.messages.append(message)
        room.messages.sort { ($0.timestamp ?? 0) < ($1.timestamp ?? 0) }
        
        // Update last message
        room.lastMessage = LastMessage(
            body: message.body,
            date: message.date,
            emoji: nil,
            locationPreview: message.locationPreview,
            filename: message.fileName,
            mimetype: message.mimetype,
            originalName: message.originalName
        )
        room.lastMessageTimestamp = message.timestamp
        
        rooms[roomJID] = room
        saveToCache()
    }
    
    /// Set room messages
    public func setRoomMessages(roomJID: String, messages: [Message]) {
        guard var room = rooms[roomJID] else { return }
        room.messages = messages.sorted { ($0.timestamp ?? 0) < ($1.timestamp ?? 0) }
        rooms[roomJID] = room
        saveToCache()
    }
    
    /// Delete message from room
    public func deleteMessage(roomJID: String, messageId: String) {
        guard var room = rooms[roomJID] else { return }
        room.messages.removeAll { $0.id == messageId }
        rooms[roomJID] = room
        saveToCache()
    }
    
    /// Update message in room
    public func updateMessage(roomJID: String, messageId: String, updates: PartialMessageUpdate) {
        guard var room = rooms[roomJID],
              let index = room.messages.firstIndex(where: { $0.id == messageId }) else {
            return
        }
        
        var message = room.messages[index]
        
        if let body = updates.body {
            message.body = body
        }
        if let isDeleted = updates.isDeleted {
            message.isDeleted = isDeleted
        }
        if let reaction = updates.reaction {
            message.reaction = reaction
        }
        
        room.messages[index] = message
        rooms[roomJID] = room
        saveToCache()
    }
    
    // MARK: - Reactions
    
    /// Set reactions on a message
    public func setReactions(
        roomJID: String,
        messageId: String,
        reactions: [String],
        from: String,
        data: [String: String]
    ) {
        guard var room = rooms[roomJID],
              let index = room.messages.firstIndex(where: { $0.id == messageId }) else {
            return
        }
        
        var message = room.messages[index]
        
        if message.reaction == nil {
            message.reaction = [:]
        }
        
        let fromId = from.components(separatedBy: "@").first ?? from
        
        if reactions.isEmpty {
            message.reaction?.removeValue(forKey: fromId)
        } else {
            message.reaction?[fromId] = ReactionMessage(emoji: reactions, data: data)
        }
        
        room.messages[index] = message
        rooms[roomJID] = room
        saveToCache()
    }
    
    // MARK: - Edit Action
    
    /// Set edit action
    public func setEditAction(_ action: EditAction?) {
        editAction = action
    }
    
    /// Clear edit action
    public func clearEditAction() {
        editAction = nil
    }
    
    // MARK: - Last Viewed Timestamp
    
    /// Set last viewed timestamp for a room
    public func setLastViewedTimestamp(roomJID: String, timestamp: Int64) {
        guard var room = rooms[roomJID] else { return }
        room.lastViewedTimestamp = timestamp
        rooms[roomJID] = room
        saveToCache()
    }
    
    // MARK: - Unread Count
    
    /// Update unread count for a room
    public func updateUnreadCount(roomJID: String, count: Int) {
        guard var room = rooms[roomJID] else { return }
        room.unreadMessages = count
        rooms[roomJID] = room
        saveToCache()
    }
    
    // MARK: - Cache Management
    
    private func saveToCache() {
        // Limit messages per room to 50 (like web)
        var roomsToSave = rooms
        for (jid, room) in roomsToSave {
            if room.messages.count > 50 {
                roomsToSave[jid] = Room(
                    id: room.id,
                    jid: room.jid,
                    name: room.name,
                    title: room.title,
                    usersCnt: room.usersCnt,
                    messages: Array(room.messages.suffix(50)),
                    isLoading: room.isLoading,
                    roomBg: room.roomBg,
                    members: room.members,
                    type: room.type,
                    createdAt: room.createdAt,
                    appId: room.appId,
                    createdBy: room.createdBy,
                    description: room.description,
                    isAppChat: room.isAppChat,
                    picture: room.picture,
                    updatedAt: room.updatedAt,
                    lastMessage: room.lastMessage,
                    lastMessageTimestamp: room.lastMessageTimestamp,
                    icon: room.icon,
                    composing: room.composing,
                    composingList: room.composingList,
                    lastViewedTimestamp: room.lastViewedTimestamp,
                    unreadMessages: room.unreadMessages,
                    noMessages: room.noMessages,
                    role: room.role,
                    messageStats: room.messageStats,
                    historyComplete: room.historyComplete
                )
            }
        }
        
        if let encoded = try? JSONEncoder().encode(roomsToSave) {
            UserDefaults.standard.set(encoded, forKey: "ethora_room_store")
        }
    }
    
    private func loadFromCache() {
        if let data = UserDefaults.standard.data(forKey: "ethora_room_store"),
           let decoded = try? JSONDecoder().decode([String: Room].self, from: data) {
            rooms = decoded
        }
    }
    
    /// Clear all rooms
    public func clearAll() {
        rooms.removeAll()
        activeRoomJID = nil
        editAction = nil
        usersSet.removeAll()
        reportRoom = ReportRoomState()
        UserDefaults.standard.removeObject(forKey: "ethora_room_store")
    }
}

// MARK: - Supporting Types

public struct EditAction {
    public let isEdit: Bool
    public let roomJid: String
    public let messageId: String
    public let text: String
    
    public init(isEdit: Bool, roomJid: String, messageId: String, text: String) {
        self.isEdit = isEdit
        self.roomJid = roomJid
        self.messageId = messageId
        self.text = text
    }
}

public struct ReportRoomState {
    public var isOpen: Bool = false
    
    public init(isOpen: Bool = false) {
        self.isOpen = isOpen
    }
}

public struct PartialRoomUpdate {
    public var usersCnt: Int?
    public var messages: [Message]?
    public var isLoading: Bool?
    public var roomBg: String?
    public var members: [RoomMember]?
    public var type: RoomType?
    public var description: String?
    public var picture: String?
    public var lastMessage: LastMessage?
    public var lastMessageTimestamp: Int64?
    public var icon: String?
    public var composing: Bool?
    public var composingList: [String]?
    public var lastViewedTimestamp: Int64?
    public var unreadMessages: Int?
    public var noMessages: Bool?
    public var role: String?
    public var messageStats: MessageStats?
    public var historyComplete: Bool?
    
    public init() {}
}

public struct PartialMessageUpdate {
    public var body: String?
    public var isDeleted: Bool?
    public var reaction: [String: ReactionMessage]?
    
    public init() {}
}
