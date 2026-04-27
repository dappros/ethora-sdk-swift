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

    /// Bare JID-ы чатов, из которых юзер вышел через «Leave» — но
    /// бэкенд `GET /chats/my` всё ещё их отдаёт. Сюда мы кладём такие
    /// комнаты, и `addRoomFromApi(...)` игнорирует их при следующем
    /// рефреше, чтобы не возвращать строку в список. На реальный re-join
    /// (см. `unhideRoom(jid:)` в обработчике XEP-0249/XEP-0045 invite)
    /// флаг снимается.
    @Published public var hiddenRoomJIDs: Set<String> = []
    
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
    
    /// Add or update a room.
    ///
    /// Behaviour matches what chat apps like Telegram expect:
    /// - If we already have this room in the store, **preserve** the
    ///   client-tracked unread state (`unreadMessages`,
    ///   `lastViewedTimestamp`). REST responses usually don't carry those
    ///   fields, so a naive overwrite would wipe every user's badge on every
    ///   `/chats/my` refresh.
    /// - If it's the first time we see this room, seed `lastViewedTimestamp`
    ///   with "now". That way the cold-start MAM refresh won't instantly
    ///   mark 50 historical messages as "unread" — everything that existed
    ///   before the user even opened the app is treated as already read.
    ///   Only messages that arrive **after** the app started will bump the
    ///   badge, which is the behaviour Telegram ships with.
    public func addRoom(_ room: Room) {
        // Если юзер недавно вышел из этой комнаты — не возвращаем её,
        // даже если REST `/chats/my` отдал её обратно. Снять hidden можно
        // только явным образом (см. `unhideRoom(jid:)`), чтобы случайный
        // фоновый рефреш не «воскрешал» только что покинутый чат.
        let bareJID = room.jid.components(separatedBy: "/").first ?? room.jid
        if hiddenRoomJIDs.contains(bareJID) {
            print("🙈 RoomStore.addRoom skipped — \(bareJID) is in hiddenRoomJIDs")
            return
        }

        var toStore = room
        if let existing = rooms[room.jid] {
            if toStore.lastViewedTimestamp == nil || (toStore.lastViewedTimestamp ?? 0) <= 0 {
                toStore.lastViewedTimestamp = existing.lastViewedTimestamp
            }
            if toStore.unreadMessages == 0 {
                toStore.unreadMessages = existing.unreadMessages
            }
        } else if (toStore.lastViewedTimestamp ?? 0) <= 0 {
            toStore.lastViewedTimestamp = Int64(Date().timeIntervalSince1970 * 1000)
        }
        rooms[room.jid] = toStore
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

    /// Помечаем комнату как «вышли из неё» — удаляем её из текущего
    /// списка и добавляем bare JID в `hiddenRoomJIDs`, чтобы
    /// `addRoomFromApi(...)` не воскресил эту комнату при ближайшем
    /// `GET /chats/my`. Используется в swipe-Leave; снимается через
    /// `unhideRoom(jid:)` при ре-инвайте.
    public func hideRoom(jid: String) {
        let bareJID = jid.components(separatedBy: "/").first ?? jid
        hiddenRoomJIDs.insert(bareJID)
        rooms.removeValue(forKey: bareJID)
        if activeRoomJID == bareJID {
            activeRoomJID = nil
        }
        saveToCache()
    }

    /// Снимает «hidden» с комнаты — нужно при ре-инвайте, чтобы
    /// XMPP-broadcast снова дошёл до UI и комната появилась в списке.
    public func unhideRoom(jid: String) {
        let bareJID = jid.components(separatedBy: "/").first ?? jid
        if hiddenRoomJIDs.remove(bareJID) != nil {
            saveToCache()
        }
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
        
        let originalMessage = room.messages[index]
        
        // Create a new message with updated values
        let updatedMessage = Message(
            id: originalMessage.id,
            user: originalMessage.user,
            date: originalMessage.date,
            body: updates.body ?? originalMessage.body,
            roomJid: originalMessage.roomJid,
            key: originalMessage.key,
            coinsInMessage: originalMessage.coinsInMessage,
            numberOfReplies: originalMessage.numberOfReplies,
            isSystemMessage: originalMessage.isSystemMessage,
            isMediafile: originalMessage.isMediafile,
            locationPreview: originalMessage.locationPreview,
            mimetype: originalMessage.mimetype,
            location: originalMessage.location,
            pending: originalMessage.pending,
            timestamp: originalMessage.timestamp,
            showInChannel: originalMessage.showInChannel,
            activeMessage: originalMessage.activeMessage,
            isReply: originalMessage.isReply,
            isDeleted: updates.isDeleted ?? originalMessage.isDeleted,
            mainMessage: originalMessage.mainMessage,
            reply: originalMessage.reply,
            reaction: updates.reaction ?? originalMessage.reaction,
            fileName: originalMessage.fileName,
            translations: originalMessage.translations,
            langSource: originalMessage.langSource,
            originalName: originalMessage.originalName,
            size: originalMessage.size,
            xmppId: originalMessage.xmppId,
            xmppFrom: originalMessage.xmppFrom
        )
        
        room.messages[index] = updatedMessage
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

    /// Recomputes `unreadMessages` for a single room from its own
    /// `messages` array vs `lastViewedTimestamp`. Mirrors the React
    /// `unreadMiddleware.computeUnreadForRoom` logic:
    /// - not counted: own messages, pending, system, delimiter, no-timestamp
    /// - if room is active → 0
    /// - if `lastViewedTimestamp == 0` (never opened) → all countable
    /// - otherwise → count of messages with `timestamp > lastViewed`
    ///
    /// Falls back to `MessageCache` when `room.messages` is empty — room-
    /// list view models don't always eagerly hydrate `room.messages` from
    /// cache, but the cache itself is always up to date.
    public func recomputeUnreadForRoom(jid: String, currentUserLocal: String) {
        guard var room = rooms[jid] else { return }

        // Active room → 0, like React.
        if activeRoomJID == jid {
            if room.unreadMessages != 0 {
                room.unreadMessages = 0
                rooms[jid] = room
                saveToCache()
            }
            return
        }

        var pool = room.messages
        if pool.isEmpty, let cached = MessageCache.shared.loadMessages(forRoomJID: jid) {
            pool = cached
        }

        let lastViewed = room.lastViewedTimestamp ?? 0
        var counted: [(id: String, ts: Int64, body: String, isMedia: Bool, isSystem: String?, sender: String)] = []
        let unread = pool.reduce(0) { acc, msg in
            guard msg.id != "delimiter-new" else { return acc }
            guard msg.isDeleted != true else { return acc }
            guard msg.pending != true else { return acc }
            guard msg.isSystemMessage != "true" else { return acc }
            let trimmed = msg.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty || msg.isMediafile == "true" else { return acc }

            let senderLocal = msg.user.xmppUsername?
                .components(separatedBy: "@").first ?? ""
            if !senderLocal.isEmpty, !currentUserLocal.isEmpty,
               senderLocal == currentUserLocal {
                return acc
            }
            let ts = msg.timestamp ?? 0
            guard ts > 0 else { return acc }
            if lastViewed > 0 && ts <= lastViewed { return acc }
            counted.append((
                id: msg.id,
                ts: ts,
                body: String(trimmed.prefix(60)),
                isMedia: msg.isMediafile == "true",
                isSystem: msg.isSystemMessage,
                sender: senderLocal
            ))
            return acc + 1
        }

        if unread > 0 {
            print("🔢 recomputeUnread room=\(jid) lastViewed=\(lastViewed) pool=\(pool.count) → unread=\(unread)")
            for c in counted {
                print("   • id=\(c.id) ts=\(c.ts) body='\(c.body)' isMedia=\(c.isMedia) isSystem=\(String(describing: c.isSystem)) sender=\(c.sender)")
            }
        }

        if room.unreadMessages != unread {
            room.unreadMessages = unread
            rooms[jid] = room
            saveToCache()
        }
    }

    /// Convenience — recompute unread for every known room.
    public func recomputeAllUnread(currentUserLocal: String) {
        for jid in rooms.keys {
            recomputeUnreadForRoom(jid: jid, currentUserLocal: currentUserLocal)
        }
    }

    /// Total unread across all rooms — for host app badge / tests.
    public var totalUnreadCount: Int {
        rooms.values.reduce(0) { $0 + max(0, $1.unreadMessages) }
    }
    
    // MARK: - Cache Management
    
    private func saveToCache() {
        // Limit messages per room to 100 (matches `MessageCache.maxCachedMessagesPerRoom`)
        var roomsToSave = rooms
        for (jid, room) in roomsToSave {
            if room.messages.count > 100 {
                roomsToSave[jid] = Room(
                    id: room.id,
                    jid: room.jid,
                    name: room.name,
                    title: room.title,
                    usersCnt: room.usersCnt,
                    messages: Array(room.messages.suffix(100)),
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
        if let encodedHidden = try? JSONEncoder().encode(hiddenRoomJIDs) {
            UserDefaults.standard.set(encodedHidden, forKey: "ethora_room_store_hidden")
        }
    }

    private func loadFromCache() {
        if let data = UserDefaults.standard.data(forKey: "ethora_room_store"),
           let decoded = try? JSONDecoder().decode([String: Room].self, from: data) {
            rooms = decoded
        }
        if let hiddenData = UserDefaults.standard.data(forKey: "ethora_room_store_hidden"),
           let decodedHidden = try? JSONDecoder().decode(Set<String>.self, from: hiddenData) {
            hiddenRoomJIDs = decodedHidden
        }
    }
    
    /// Clear all rooms
    public func clearAll() {
        rooms.removeAll()
        activeRoomJID = nil
        editAction = nil
        usersSet.removeAll()
        reportRoom = ReportRoomState()
        hiddenRoomJIDs.removeAll()
        UserDefaults.standard.removeObject(forKey: "ethora_room_store")
        UserDefaults.standard.removeObject(forKey: "ethora_room_store_hidden")
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
