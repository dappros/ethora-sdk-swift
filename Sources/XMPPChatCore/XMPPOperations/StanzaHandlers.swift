//
//  StanzaHandlers.swift
//  XMPPChatCore
//
//  Handles incoming XMPP stanzas and converts them to messages
//  Complete translation from stanzaHandlers.ts
//

import Foundation

public class StanzaHandlers {
    weak var client: XMPPClient?
    
    // Callbacks for different events
    var onMessageReceived: ((Message, String) -> Void)? // (message, roomJID)
    var onHistoryMessageReceived: ((Message, String) -> Void)? // (message, roomJID)
    var onReactionReceived: ((String, String, [String], String, [String: String]) -> Void)? // (roomJID, messageId, reactions, from, data)
    var onMessageDeleted: ((String, String) -> Void)? // (roomJID, messageId)
    var onMessageEdited: ((String, String, String) -> Void)? // (roomJID, messageId, newText)
    var onComposingChanged: ((String, [String], Bool) -> Void)? // (roomJID, composingList, isComposing)
    var onPresenceInRoom: ((String, String) -> Void)? // (roomJID, role)
    var onChatInvite: ((String) -> Void)? // (roomJID)
    var onRoomKicked: ((String) -> Void)? // (roomJID)
    var onGetChatRooms: (([RoomData]) -> Void)? // (rooms)
    var onNewRoomCreated: ((String) -> Void)? // (roomJID)
    var onGetLastMessageArchive: ((String, Bool, Int64?, Int64?) -> Void)? // (roomJID, historyComplete, lastMessageTimestamp, firstMessageTimestamp)
    var onMessageError: ((String) -> Void)? // (roomJID)
    
    // Get-history collectors: queryId -> (stanza, roomJID) -> Void
    private var getHistoryCollectors: [String: (XMPPStanza, String) -> Void] = [:]
    
    public struct RoomData {
        let jid: String
        let name: String
        let usersCnt: Int
        let roomBg: String?
        let icon: String?
    }
    
    init(client: XMPPClient) {
        self.client = client
    }
    
    // MARK: - Public Handler Methods (called from HandleStanzas)
    
    /// Handle real-time messages (onRealtimeMessage from TypeScript)
    public func onRealtimeMessage(_ stanza: XMPPStanza) {
        // Match TypeScript: Skip MUC invites first
        let mucX = stanza.getChildren("x").first { x in
            x.attributes["xmlns"] == "http://jabber.org/protocol/muc#user" &&
            x.getChild("invite") != nil
        }
        if mucX != nil {
            return
        }
        
        // Match TypeScript: Skip if it's a result (MAM), composing, paused, subject, or special messages
        if stanza.getChild("result") != nil ||
           stanza.getChild("composing") != nil ||
           stanza.getChild("paused") != nil ||
           stanza.getChild("subject") != nil ||
           stanza.name == "iq" ||
           stanza.attributes["id"] == "deleteMessageStanza" ||
           (stanza.attributes["id"]?.contains("message-reaction") ?? false) {
            return
        }
        
        // Match TypeScript: try { const { data } = await getDataFromXml(stanza); } catch (error) { handleErrorMessageStanza(stanza); return; }
        guard let messageData = MessageParser.getDataFromStanza(stanza) else {
            // Handle error
            if stanza.attributes["type"] == "error" {
                handleErrorMessageStanza(stanza)
            }
            return
        }
        
        // Match TypeScript: if (!data) { console.log('No data in stanza'); return; }
        guard !messageData.dataAttrs.isEmpty else {
            print("⚠️ No data in stanza")
            return
        }
        
        // Match TypeScript: const message = await createMessageFromXml({ data, id, body, ...rest });
        // MessageParser.createMessageFromData now returns Message (from Models) directly
        let message = MessageParser.createMessageFromData(messageData)
        
        // Match TypeScript: roomJID: stanza.attrs.from.split('/')[0]
        let roomJID = stanza.attributes["from"]?.components(separatedBy: "/").first ?? message.roomJid
        
        onMessageReceived?(message, roomJID)
    }
    
    /// Handle message history from MAM (onMessageHistory from TypeScript)
    /// Matches TypeScript EXACTLY:
    /// if (stanza.is('message') && stanza.children[0].attrs.xmlns === 'urn:xmpp:mam:2')
    public func onMessageHistory(_ stanza: XMPPStanza) {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📥 onMessageHistory CALLED")
        print("   Stanza name: \(stanza.name)")
        print("   Stanza from: \(stanza.attributes["from"] ?? "nil")")
        print("   Stanza to: \(stanza.attributes["to"] ?? "nil")")
        print("   Children count: \(stanza.children.count)")
        if let firstChild = stanza.children.first {
            print("   First child name: \(firstChild.name)")
            print("   First child xmlns: \(firstChild.attributes["xmlns"] ?? "nil")")
        }
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        // Match TypeScript EXACTLY: stanza.is('message') && stanza.children[0].attrs.xmlns === 'urn:xmpp:mam:2'
        guard stanza.name == "message",
              let firstChild = stanza.children.first,
              firstChild.attributes["xmlns"] == "urn:xmpp:mam:2" else {
            print("⚠️ onMessageHistory: Stanza doesn't match MAM message format - SKIPPING")
            return
        }
        
        print("✅ onMessageHistory: Stanza matches MAM message format")
        
        // Check if this is part of an active get-history query
        // Look for active collectors that match this room
        let roomJID = stanza.attributes["from"] ?? ""
        var handledByGetHistory = false
        
        for (queryId, collector) in getHistoryCollectors {
            // Pass stanza to collector - it will decide if it matches
            collector(stanza, roomJID)
            handledByGetHistory = true
            print("✅✅✅ onMessageHistory: Collected for get-history query: \(queryId)")
        }
        
        // Match TypeScript: const { data, id, body, ...rest } = await getDataFromXml(stanza);
        guard let messageData = MessageParser.getDataFromStanza(stanza) else {
            print("❌ onMessageHistory: Failed to parse message data from stanza")
            return
        }
        
        print("✅ onMessageHistory: Message data parsed successfully")
        print("   Message ID: \(messageData.id)")
        print("   Message body: \(messageData.body?.prefix(50) ?? "nil")...")
        print("   Data attrs count: \(messageData.dataAttrs.count)")
        
        // Match TypeScript: if (!data) { console.log('No data in stanza'); return; }
        guard !messageData.dataAttrs.isEmpty else {
            print("⚠️ onMessageHistory: No data in stanza - SKIPPING")
            return
        }
        
        // Match TypeScript: const message = await createMessageFromXml({ data, id, body, ...rest });
        // MessageParser.createMessageFromData now returns Message (from Models) directly
        let message = MessageParser.createMessageFromData(messageData)
        
        print("✅ onMessageHistory: Message object created")
        print("   Message ID: \(message.id)")
        print("   Message roomJid: \(message.roomJid)")
        print("   Message body: \(message.body.prefix(50))...")
        print("   Message timestamp: \(message.timestamp?.description ?? "nil")")
        
        // Match TypeScript: checkSingleUser and insertUsers (skip for now - would need user store)
        // const fixedUser = await checkSingleUser(store.getState().rooms.usersSet, message.user.id);
        // if (fixedUser) { store.dispatch(insertUsers({ newUsers: [fixedUser] })); }
        
        // Match TypeScript: store.dispatch(addRoomMessage({ roomJID: stanza.attrs.from, message }))
        // IMPORTANT: Use stanza.attrs.from directly (NOT split) - matches TypeScript exactly
        let roomJIDForMessage = stanza.attributes["from"] ?? ""
        
        print("📤 onMessageHistory: Calling onHistoryMessageReceived callback")
        print("   Room JID: \(roomJIDForMessage)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        // Call callback (equivalent to store.dispatch(addRoomMessage))
        onHistoryMessageReceived?(message, roomJIDForMessage)
        
        print("✅ onMessageHistory: Callback executed")
    }
    
    /// Register a get-history collector
    public func registerGetHistoryCollector(queryId: String, roomJID: String, collector: @escaping (XMPPStanza, String) -> Void) {
        getHistoryCollectors[queryId] = collector
        print("📝 Registered get-history collector: queryId=\(queryId), roomJID=\(roomJID)")
    }
    
    /// Unregister a get-history collector
    public func unregisterGetHistoryCollector(queryId: String) {
        getHistoryCollectors.removeValue(forKey: queryId)
        print("🗑️ Unregistered get-history collector: queryId=\(queryId)")
    }
    
    /// Handle reaction messages (onReactionMessage from TypeScript)
    public func onReactionMessage(_ stanza: XMPPStanza) {
        guard let id = stanza.attributes["id"],
              id.contains("message-reaction"),
              let reactions = stanza.getChild("reactions"),
              let stanzaId = stanza.getChild("stanza-id") else {
            return
        }
        
        let roomJid = stanzaId.attributes["by"] ?? ""
        let timestamp = stanzaId.attributes["id"] ?? ""
        let messageId = reactions.attributes["id"] ?? ""
        let from = reactions.attributes["from"] ?? ""
        
        // Match TypeScript: reactions.getChildren('reaction').map((reaction) => reaction.text())
        let emojiList = reactions.getChildren("reaction").compactMap { $0.text }
        
        // Get data element
        let data = stanza.getChild("data")
        let dataAttrs = data?.attributes ?? [:]
        
        print("👍 Reaction: room=\(roomJid), messageId=\(messageId), reactions=\(emojiList.joined(separator: ","))")
        
        onReactionReceived?(roomJid, messageId, emojiList, from, dataAttrs)
    }
    
    /// Handle reaction history (onReactionHistory from TypeScript)
    public func onReactionHistory(_ stanza: XMPPStanza) {
        // Match TypeScript: stanza.getChild('result')?.getChild('forwarded')?.getChild('message')?.getChild('reactions')
        guard let result = stanza.getChild("result"),
              let forwarded = result.getChild("forwarded"),
              let message = forwarded.getChild("message") else {
            return
        }
        
        let reactions = message.getChild("reactions")
        let data = message.getChild("data")
        let stanzaId = message.getChild("stanza-id")
        
        // Match TypeScript: if (!reactions && !data && !stanzaId && !reactions?.attrs) { return; }
        guard reactions != nil || data != nil || stanzaId != nil else {
            return
        }
        
        guard let reactions = reactions,
              let stanzaId = stanzaId else {
            return
        }
        
        let messageId = reactions.attributes["id"] ?? ""
        
        // Match TypeScript: reactions.children.map((emoji) => emoji.children[0])
        let reactionList = reactions.getChildren("reaction").compactMap { reaction in
            reaction.children.first?.text
        }
        
        let from = reactions.attributes["from"] ?? ""
        let dataReaction: [String: String] = [
            "senderFirstName": data?.attributes["senderFirstName"] ?? "",
            "senderLastName": data?.attributes["senderLastName"] ?? ""
        ]
        
        let roomJid = stanzaId.attributes["by"] ?? ""
        let timestamp = stanzaId.attributes["id"] ?? ""
        
        print("👍 Reaction history: room=\(roomJid), messageId=\(messageId), reactions=\(reactionList.joined(separator: ","))")
        
        onReactionReceived?(roomJid, messageId, reactionList, from, dataReaction)
    }
    
    /// Handle delete message (onDeleteMessage from TypeScript)
    public func onDeleteMessage(_ stanza: XMPPStanza) {
        guard stanza.attributes["id"] == "deleteMessageStanza",
              let deleted = stanza.getChild("delete"),
              let stanzaId = stanza.getChild("stanza-id") else {
            return
        }
        
        let roomJID = stanzaId.attributes["by"] ?? ""
        let messageId = deleted.attributes["id"] ?? ""
        
        print("🗑️ Message deleted: room=\(roomJID), messageId=\(messageId)")
        
        onMessageDeleted?(roomJID, messageId)
    }
    
    /// Handle edit message (onEditMessage from TypeScript)
    public func onEditMessage(_ stanza: XMPPStanza) {
        guard let id = stanza.attributes["id"],
              id.contains("edit-message"),
              let stanzaId = stanza.getChild("stanza-id"),
              let replace = stanza.getChild("replace") else {
            return
        }
        
        let roomJID = stanzaId.attributes["by"] ?? ""
        let messageId = replace.attributes["id"] ?? ""
        let newText = replace.attributes["text"] ?? ""
        
        print("✏️ Message edited: room=\(roomJID), messageId=\(messageId)")
        
        onMessageEdited?(roomJID, messageId, newText)
    }
    
    /// Handle composing indicators (handleComposing from TypeScript)
    public func handleComposing(_ stanza: XMPPStanza, currentUser: String) {
        let isComposing = stanza.getChild("composing") != nil
        let isPaused = stanza.getChild("paused") != nil
        
        // Debug: Log all composing/paused stanzas
        if isComposing || isPaused {
            print("⌨️ StanzaHandlers: Received \(isComposing ? "composing" : "paused") stanza")
            print("   From: \(stanza.attributes["from"] ?? "unknown")")
        }
        
        guard isComposing || isPaused,
              let from = stanza.attributes["from"] else {
            return
        }
        
        let parts = from.components(separatedBy: "/")
        guard parts.count >= 2 else {
            print("⌨️ StanzaHandlers: Invalid from format (no resource): \(from)")
            return
        }
        
        let composingUser = parts[1]
        let chatJID = parts[0]
        
        // Match TypeScript: Skip own typing indicators
        let normalizedCurrentUser = currentUser.lowercased().replacingOccurrences(of: "_", with: "")
        let normalizedComposingUser = composingUser.lowercased().replacingOccurrences(of: "_", with: "")
        
        guard normalizedCurrentUser != normalizedComposingUser else {
            print("⌨️ StanzaHandlers: Skipping own typing indicator")
            return
        }
        
        var composingList: [String] = []
        
        // Match TypeScript: !!stanza?.getChild('composing') ? composingList.push(...) : composingList.pop()
        if isComposing {
            let fullName = stanza.getChild("data")?.attributes["fullName"] ?? composingUser
            if !composingList.contains(fullName) {
                composingList.append(fullName)
            }
        }
        // When paused, composingList stays empty (user stopped typing)
        
        print("⌨️ StanzaHandlers: Composing changed - room=\(chatJID), composing=\(isComposing), user=\(composingUser), list=\(composingList)")
        
        onComposingChanged?(chatJID, composingList, isComposing)
    }
    
    /// Handle presence in room (onPresenceInRoom from TypeScript)
    public func onPresenceInRoom(_ stanza: XMPPStanza) {
        // Match TypeScript: stanza.attrs.id === 'presenceInRoom' && !stanza.getChild('error')
        guard stanza.attributes["id"] == "presenceInRoom",
              stanza.getChild("error") == nil else {
            return
        }
        
        let roomJID = stanza.attributes["from"]?.components(separatedBy: "/").first ?? ""
        
        // Mark that we've received a presence response for this room
        // This prevents duplicate presence sends
        client?.markPresenceResponseReceived(for: roomJID)
        
        // Match TypeScript: stanza?.children[1]?.children[0]?.attrs.role
        var role: String = ""
        if stanza.children.count > 1 {
            let secondChild = stanza.children[1]
            if secondChild.children.count > 0,
               let firstGrandChild = secondChild.children.first {
                role = firstGrandChild.attributes["role"] ?? ""
            }
        }
        
        print("👤 Presence in room: room=\(roomJID), role=\(role)")
        
        onPresenceInRoom?(roomJID, role)
    }
    
    /// Handle chat invite (onChatInvite from TypeScript)
    public func onChatInvite(_ stanza: XMPPStanza, client: XMPPClient?) {
        guard stanza.name == "message" else {
            return
        }
        
        let chatId = stanza.attributes["from"] ?? ""
        let xEls = stanza.getChildren("x")
        
        for el in xEls {
            guard el.getChild("invite") != nil else {
                continue
            }
            
            // Check if room already exists (would need room store)
            // For now, just notify about invite
            print("📨 Chat invite: room=\(chatId)")
            
            onChatInvite?(chatId)
            break
        }
    }
    
    /// Handle room kicked (onRoomKicked from TypeScript)
    public func onRoomKicked(_ stanza: XMPPStanza) {
        // Match TypeScript: stanza.is('presence') && stanza.attrs.type === 'unavailable'
        guard stanza.name == "presence",
              stanza.attributes["type"] == "unavailable",
              let xElement = stanza.getChild("x") else {
            return
        }
        
        let statusElements = xElement.getChildren("status")
        guard !statusElements.isEmpty else {
            return
        }
        
        // Match TypeScript: statusCodes.includes('110') && statusCodes.includes('321')
        let statusCodes = statusElements.compactMap { $0.attributes["code"] }
        guard statusCodes.contains("110") && statusCodes.contains("321") else {
            return
        }
        
        let roomJid = stanza.attributes["from"]?.components(separatedBy: "/").first ?? ""
        
        print("🚪 Room kicked: room=\(roomJid)")
        
        onRoomKicked?(roomJid)
    }
    
    /// Handle get chat rooms (onGetChatRooms from TypeScript)
    public func onGetChatRooms(_ stanza: XMPPStanza, client: XMPPClient?) {
        // Match TypeScript: stanza.attrs.id === 'getUserRooms' && Array.isArray(stanza.getChild('query')?.children)
        guard stanza.attributes["id"] == "getUserRooms",
              let query = stanza.getChild("query") else {
            return
        }
        
        var rooms: [RoomData] = []
        
        for result in query.children {
            let attrs = result.attributes
            
            let roomData = RoomData(
                jid: attrs["jid"] ?? "",
                name: attrs["name"] ?? "",
                usersCnt: Int(attrs["users_cnt"] ?? "0") ?? 0,
                roomBg: attrs["room_background"] == "none" ? nil : attrs["room_background"],
                icon: attrs["room_thumbnail"] == "none" ? nil : attrs["room_thumbnail"]
            )
            
            rooms.append(roomData)
        }
        
        print("🏠 Got chat rooms: \(rooms.count) rooms")
        
        onGetChatRooms?(rooms)
    }
    
    /// Handle new room created (onNewRoomCreated from TypeScript)
    public func onNewRoomCreated(_ stanza: XMPPStanza, client: XMPPClient?) {
        let roomJID = stanza.attributes["from"] ?? ""
        
        print("🆕 New room created: room=\(roomJID)")
        
        onNewRoomCreated?(roomJID)
    }
    
    /// Handle get room info (onGetRoomInfo from TypeScript)
    public func onGetRoomInfo(_ stanza: XMPPStanza) {
        // Match TypeScript: stanza.attrs.id === 'roomInfo' && !stanza.getChild('error')
        guard stanza.attributes["id"] == "roomInfo",
              stanza.getChild("error") == nil else {
            return
        }
        
        // Handle room info (implementation depends on requirements)
        print("ℹ️ Room info received")
    }
    
    /// Handle get last message archive (onGetLastMessageArchive from TypeScript)
    /// Handles IQ result with <fin> element from get-history queries
    public func onGetLastMessageArchive(_ stanza: XMPPStanza) {
        // Match TypeScript: stanza.attrs?.id && stanza.attrs?.id.toString().includes('get-history')
        guard stanza.name == "iq",
              stanza.attributes["type"] == "result",
              let id = stanza.attributes["id"],
              id.contains("get-history") else {
            return
        }
        
        // Try to get <fin> with namespace, fallback to without namespace
        let fin = stanza.getChild("fin", xmlns: "urn:xmpp:mam:2") ?? stanza.getChild("fin")
        guard let finElement = fin else {
            print("⚠️ onGetLastMessageArchive: No <fin> element found")
            return
        }
        
        // Try to get <set> with namespace, fallback to without namespace
        let set = finElement.getChild("set", xmlns: "http://jabber.org/protocol/rsm") ?? finElement.getChild("set")
        guard let setElement = set else {
            print("⚠️ onGetLastMessageArchive: No <set> element found")
            return
        }
        
        // Extract room JID from 'to' or 'from' attribute
        let roomJid = (stanza.attributes["from"] ?? stanza.attributes["to"] ?? "")
            .components(separatedBy: "/").first ?? ""
        
        guard !roomJid.isEmpty else {
            print("⚠️ onGetLastMessageArchive: No room JID found")
            return
        }
        
        guard let complete = finElement.attributes["complete"] else {
            print("⚠️ onGetLastMessageArchive: No 'complete' attribute in <fin>")
            return
        }
        
        // Match TypeScript: getBooleanFromString(fin.attrs.complete)
        let historyComplete = complete.lowercased() == "true" || complete == "1"
        
        // Extract count, last, and first from <set>
        let countText = setElement.getChild("count")?.text ?? ""
        let last = setElement.getChild("last")?.text ?? ""
        let first = setElement.getChild("first")?.text ?? ""
        
        let count = Int(countText) ?? 0
        let lastMessageTimestamp = Int64(last) ?? nil
        let firstMessageTimestamp = Int64(first) ?? nil
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📚 GET-HISTORY IQ RESULT RECEIVED:")
        print("   Room: \(roomJid)")
        print("   Query ID: \(id)")
        print("   Complete: \(historyComplete)")
        print("   Count: \(count)")
        print("   First: \(firstMessageTimestamp ?? 0)")
        print("   Last: \(lastMessageTimestamp ?? 0)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        // Post notification for ChatRoomViewModel to update room
        NotificationCenter.default.post(
            name: NSNotification.Name("XMPPHistoryComplete"),
            object: nil,
            userInfo: [
                "roomJID": roomJid,
                "historyComplete": historyComplete,
                "count": count,
                "firstMessageTimestamp": firstMessageTimestamp as Any,
                "lastMessageTimestamp": lastMessageTimestamp as Any
            ]
        )
        
        // Call existing callback
        onGetLastMessageArchive?(roomJid, historyComplete, lastMessageTimestamp, firstMessageTimestamp)
    }
    
    /// Handle message error (onMessageError from TypeScript)
    public func onMessageError(_ stanza: XMPPStanza, client: XMPPClient?) {
        // Match TypeScript: stanza.name === 'message' && stanza.attrs.type === 'error'
        guard stanza.name == "message",
              stanza.attributes["type"] == "error" else {
            return
        }
        
        let roomJID = stanza.attributes["from"]?.components(separatedBy: "/").first ?? ""
        
        guard !roomJID.isEmpty, let client = client else {
            return
        }
        
        print("❌ Message error: room=\(roomJID)")
        
        // Match TypeScript: Send presence and retry messages
        // This would need to be implemented based on message queue logic
        onMessageError?(roomJID)
    }
    
    /// Handle error message stanza (handleErrorMessageStanza from TypeScript)
    private func handleErrorMessageStanza(_ stanza: XMPPStanza) -> XMPPErrorInfo? {
        guard stanza.name == "message",
              stanza.attributes["type"] == "error",
              let errorEl = stanza.getChild("error") else {
            return nil
        }
        
        // Find condition element
        var condition: String = "unknown"
        for child in errorEl.children {
            if child.name != "text",
               child.attributes["xmlns"] == "urn:ietf:params:xml:ns:xmpp-stanzas" {
                condition = child.name
                break
            }
        }
        
        // Find text element
        let textEl = errorEl.getChildren("text").first { text in
            text.attributes["xmlns"] == "urn:ietf:params:xml:ns:xmpp-stanzas"
        }
        
        let errorInfo = XMPPErrorInfo(
            type: stanza.attributes["type"] ?? "",
            id: stanza.attributes["id"] ?? "",
            from: stanza.attributes["from"] ?? "",
            to: stanza.attributes["to"] ?? "",
            body: stanza.getChild("body")?.text,
            condition: condition,
            message: textEl?.text ?? ""
        )
        
        print("❌ XMPP Error: \(errorInfo.message) (condition: \(errorInfo.condition))")
        
        return errorInfo
    }
}

public struct XMPPErrorInfo {
    let type: String
    let id: String
    let from: String
    let to: String
    let body: String?
    let condition: String
    let message: String
}
