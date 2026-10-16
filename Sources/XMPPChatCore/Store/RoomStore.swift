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

    /// Bare JIDs of chats the user has left via "Leave" — but the
    /// backend `GET /chats/my` still returns them. We park such rooms
    /// here so `addRoomFromApi(...)` skips them on the next refresh and
    /// the row doesn't pop back into the list. The flag is cleared on a
    /// genuine re-join (see `unhideRoom(jid:)` in the XEP-0249/XEP-0045
    /// invite handler).
    @Published public var hiddenRoomJIDs: Set<String> = []
    
    // Edit action state
    @Published public var editAction: EditAction?
    
    // Users set (for quick lookup)
    @Published public var usersSet: [String: RoomMember] = [:]
    
    // Report room state
    @Published public var reportRoom: ReportRoomState = ReportRoomState()
    
    // Loading text
    @Published public var loadingText: String?

    /// A request to show one archived message in its room (from message search,
    /// a notification or a link). The open chat fulfils it and clears it.
    @Published public var pendingJump: PendingJump?
    
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
        // If the user just left this room — don't bring it back, even
        // if REST `/chats/my` returned it. The hidden flag is only
        // cleared explicitly (see `unhideRoom(jid:)`), so an incidental
        // background refresh can't "resurrect" a chat the user has
        // just walked out of.
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

    /// Marks a room as "left" — removes it from the current list and
    /// adds the bare JID to `hiddenRoomJIDs` so `addRoomFromApi(...)`
    /// won't resurrect this room on the next `GET /chats/my`. Used by
    /// the swipe-Leave action; cleared via `unhideRoom(jid:)` on
    /// re-invite.
    public func hideRoom(jid: String) {
        let bareJID = jid.components(separatedBy: "/").first ?? jid
        hiddenRoomJIDs.insert(bareJID)
        rooms.removeValue(forKey: bareJID)
        if activeRoomJID == bareJID {
            activeRoomJID = nil
        }
        saveToCache()
    }

    /// Clears the "hidden" flag for a room — needed on re-invite so
    /// XMPP broadcasts reach the UI again and the room reappears in
    /// the list.
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
        if let title = updates.title {
            room.title = title
        }
        if let name = updates.name {
            room.name = name
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
        if let muted = updates.muted {
            room.muted = muted
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

        // Call-log rows merge per callId. The local entry and the server copy
        // collapse into one, and the longer duration wins.
        if let meta = message.callLog, !meta.callId.isEmpty,
           let index = room.messages.firstIndex(where: { $0.callLog?.callId == meta.callId }) {
            guard (room.messages[index].callLog?.durationMs ?? 0) < meta.durationMs else { return }
            room.messages[index] = message
            rooms[roomJID] = room
            saveToCache()
            return
        }
        
        let stored = applyPendingReactions(to: message, roomJID: roomJID)
        room.messages.append(stored)
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
    
    /// Applies the closing `<fin>` of one paging page: moves the archive cursor
    /// (`messageStats.firstMessageTimestamp`) and the `historyComplete` flag.
    /// - Parameter before: the cursor the page was requested with (nil for a latest page).
    public func applyHistoryPage(roomJID: String, before: Int64?, fin: MamCursor.Fin) {
        guard let room = rooms[roomJID] else { return }
        var stats = room.messageStats ?? MessageStats()
        stats.firstMessageTimestamp = MamCursor.nextCursor(
            current: stats.firstMessageTimestamp,
            before: before,
            fin: fin,
            hadMessages: !room.messages.isEmpty
        )
        var update = PartialRoomUpdate()
        update.messageStats = stats
        update.historyComplete = fin.complete
        updateRoom(jid: roomJID, updates: update)
    }

    /// Set room messages
    public func setRoomMessages(roomJID: String, messages: [Message]) {
        guard var room = rooms[roomJID] else { return }
        room.messages = messages
            .map { applyPendingReactions(to: $0, roomJID: roomJID) }
            .sorted { ($0.timestamp ?? 0) < ($1.timestamp ?? 0) }
        rooms[roomJID] = room
        saveToCache()
    }
    
    /// Tombstone a message in a room.
    ///
    /// Matches the React `deleteRoomMessage` reducer
    /// (`ethora-chat-component/src/roomStore/roomsSlice.ts`) and the
    /// Kotlin SDK: the row stays in place so the bubble can render a
    /// "message deleted" placeholder and so reply/quoting anchors that
    /// reference this id don't dangle. Media-side fields and reactions
    /// are cleared so the placeholder doesn't show stale attachments.
    public func deleteMessage(roomJID: String, messageId: String) {
        guard var room = rooms[roomJID],
              let index = room.messages.firstIndex(where: { $0.id == messageId }) else {
            return
        }
        let original = room.messages[index]
        room.messages[index] = Message(
            id: original.id,
            user: original.user,
            date: original.date,
            body: "",
            roomJid: original.roomJid,
            key: original.key,
            coinsInMessage: original.coinsInMessage,
            numberOfReplies: original.numberOfReplies,
            isSystemMessage: original.isSystemMessage,
            isMediafile: "false",
            locationPreview: nil,
            mimetype: nil,
            location: nil,
            pending: original.pending,
            pendingSince: original.pendingSince,
            failed: original.failed,
            timestamp: original.timestamp,
            showInChannel: original.showInChannel,
            activeMessage: original.activeMessage,
            isReply: original.isReply,
            isDeleted: true,
            mainMessage: original.mainMessage,
            reply: original.reply,
            reaction: nil,
            fileName: nil,
            translations: original.translations,
            langSource: original.langSource,
            originalName: original.originalName,
            size: original.size,
            xmppId: original.xmppId,
            xmppFrom: original.xmppFrom,
            waveForm: nil,
            wasEdited: original.wasEdited
        )
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
            xmppFrom: originalMessage.xmppFrom,
            waveForm: originalMessage.waveForm,
            wasEdited: updates.wasEdited ?? originalMessage.wasEdited
        )

        room.messages[index] = updatedMessage
        rooms[roomJID] = room
        saveToCache()
    }

    // MARK: - Reactions

    /// Set one reactor's reactions on a message (web `setReactions` reducer).
    ///
    /// `from` is the reactor JID; the key is its localpart. An empty
    /// `reactions` list records a removal. A newer `timestamp` wins over an
    /// older one for the same reactor. When the target message is not loaded
    /// yet, the update is held and applied when that message is added.
    public func setReactions(
        roomJID: String,
        messageId: String,
        reactions: [String],
        from: String,
        data: [String: String],
        timestamp: Int64? = nil
    ) {
        let reactorKey = MessageReactions.reactorKey(fromJID: from)
        guard !reactorKey.isEmpty else { return }

        guard var room = rooms[roomJID],
              let index = room.messages.firstIndex(where: { $0.id == messageId }) else {
            holdPendingReaction(
                roomJID: roomJID,
                messageId: messageId,
                reactorKey: reactorKey,
                update: PendingReaction(emoji: reactions, data: data, timestamp: timestamp)
            )
            return
        }

        var message = room.messages[index]
        message.reaction = MessageReactions.apply(
            message.reaction,
            reactorKey: reactorKey,
            emoji: reactions,
            data: data,
            timestamp: timestamp
        )

        room.messages[index] = message
        rooms[roomJID] = room
        saveToCache()
    }

    /// A reaction whose target message has not arrived yet.
    struct PendingReaction {
        let emoji: [String]
        let data: [String: String]
        let timestamp: Int64?
    }

    /// Reactions held per room and message until the target is added. Bounded
    /// so a room with many unresolved targets cannot grow without limit.
    private static let maxPendingReactionTargets = 500
    private var pendingReactions: [String: [String: [String: PendingReaction]]] = [:]

    private func holdPendingReaction(roomJID: String, messageId: String, reactorKey: String, update: PendingReaction) {
        var perRoom = pendingReactions[roomJID] ?? [:]
        if perRoom[messageId] == nil, perRoom.count >= Self.maxPendingReactionTargets {
            return
        }
        var perMessage = perRoom[messageId] ?? [:]
        if let stored = perMessage[reactorKey]?.timestamp, let incoming = update.timestamp, stored > incoming {
            return
        }
        perMessage[reactorKey] = update
        perRoom[messageId] = perMessage
        pendingReactions[roomJID] = perRoom
    }

    /// Applies held reactions to a message that has just been added to a room.
    private func applyPendingReactions(to message: Message, roomJID: String) -> Message {
        guard var perRoom = pendingReactions[roomJID],
              let held = perRoom.removeValue(forKey: message.id) else {
            return message
        }
        pendingReactions[roomJID] = perRoom.isEmpty ? nil : perRoom
        var result = message
        for (reactorKey, update) in held {
            result.reaction = MessageReactions.apply(
                result.reaction,
                reactorKey: reactorKey,
                emoji: update.emoji,
                data: update.data,
                timestamp: update.timestamp
            )
        }
        return result
    }
    
    // MARK: - Receipts and Read Markers

    /// Records a XEP-0184 delivery receipt on the matching message. Matches the
    /// archive id or the sent id, since an outgoing message may be known by either.
    /// Not written to the room cache on every receipt; the chat view model
    /// persists its own copy, which carries the same field.
    public func setReceivedReceipt(
        roomJID: String,
        messageId: String,
        fromXmppUsername: String,
        timestamp: Int64
    ) {
        guard !fromXmppUsername.isEmpty,
              var room = rooms[roomJID],
              let index = room.messages.firstIndex(where: { $0.id == messageId || $0.xmppId == messageId }) else {
            return
        }
        var message = room.messages[index]
        var receivedBy = message.receivedBy ?? [:]
        receivedBy[fromXmppUsername] = timestamp
        message.receivedBy = receivedBy
        room.messages[index] = message
        rooms[roomJID] = room
    }

    /// Records a XEP-0333 read marker: the newest message `xmppUsername` has
    /// displayed in the room. One watermark per member, not one per message.
    public func setDisplayedMarker(roomJID: String, xmppUsername: String, messageId: String) {
        guard !xmppUsername.isEmpty, !messageId.isEmpty, var room = rooms[roomJID] else { return }
        var watermarks = room.lastDisplayedByUser ?? [:]
        watermarks[xmppUsername] = messageId
        room.lastDisplayedByUser = watermarks
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
            // Count ONLY messages with a non-empty `body`. This matches
            // what `RoomListView.getLastMessage` shows as the room
            // preview's lastMessage and removes "phantom unread" — the
            // case where the pool holds media stanzas with an empty
            // body (or other service frames) that the UI renders as
            // "No messages yet" yet unread keeps ticking. Real media
            // arrives in `RoomStore` via `SendMedia` along a different
            // path with a textual body already set (`fileName` /
            // `media`), so this check doesn't drop those.
            let trimmed = msg.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return acc }

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

        if pool.count > 0 || unread > 0 {
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
        pendingReactions.removeAll()
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
    public var title: String?
    public var name: String?
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
    public var muted: Bool?
    
    public init() {}
}

public struct PartialMessageUpdate {
    public var body: String?
    public var isDeleted: Bool?
    public var reaction: [String: ReactionMessage]?
    public var wasEdited: Bool?

    public init() {}
}
