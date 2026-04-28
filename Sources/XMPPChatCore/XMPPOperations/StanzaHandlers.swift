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
        
        // Match TypeScript: try { const { data } = await getDataFromXml(stanza); } catch (error) { handleErrorMessageStanza(stanza); return; }
        guard let messageData = MessageParser.getDataFromStanza(stanza) else {
            // Match TypeScript: handleErrorMessageStanza(stanza)
            if stanza.attributes["type"] == "error" {
                onMessageError?(stanza.attributes["from"]?.components(separatedBy: "/").first ?? "")
            }
            return
        }
        
        // Match TypeScript: const message = await createMessageFromXml({ data, id, body, ...rest });
        let message = MessageParser.createMessageFromData(messageData)
        
        // Match TypeScript: roomJID: stanza.attrs.from.split('/')[0]
        let roomJID = stanza.attributes["from"]?.components(separatedBy: "/").first ?? message.roomJid
        
        onMessageReceived?(message, roomJID)
    }
    
    /// Handle message history from MAM (onMessageHistory from TypeScript)
    /// Matches TypeScript EXACTLY:
    /// if (stanza.is('message') && stanza.children[0].attrs.xmlns === 'urn:xmpp:mam:2')
    public func onMessageHistory(_ stanza: XMPPStanza) {
        // Match TypeScript EXACTLY: stanza.is('message') && stanza.children[0].attrs.xmlns === 'urn:xmpp:mam:2'
        guard stanza.name == "message",
              let firstChild = stanza.children.first,
              firstChild.attributes["xmlns"] == "urn:xmpp:mam:2" else {
            return
        }

        // Check if this is part of an active get-history query
        let roomJID = stanza.attributes["from"] ?? ""
        for (queryId, collector) in getHistoryCollectors {
            collector(stanza, roomJID)
        }

        // XEP-0308 replay from MAM. The stored sequence is:
        //   1) the original `<message><body>…</body></message>` (pre-edit)
        //   2) a separate `<message id="edit-message-…"><replace .../></message>`
        // Without this branch the second stanza falls through to
        // `MessageParser.getDataFromStanza` (returns nil — no `<data>`),
        // gets dropped, and the edit is lost forever once history is
        // replayed: the original-body stanza in step 1 silently overwrites
        // any locally-applied edit. Detect the replace stanza here and
        // route through the same callback realtime edits use.
        if let result = firstChild.name == "result" ? firstChild : stanza.getChild("result"),
           let forwarded = result.getChild("forwarded"),
           let inner = forwarded.getChild("message"),
           let replace = inner.getChild("replace") {
            let editRoomJID = inner.getChild("stanza-id")?.attributes["by"]
                ?? stanza.attributes["from"]
                ?? ""
            let editMessageId = replace.attributes["id"] ?? ""
            let newText = replace.attributes["text"] ?? ""
            if !editMessageId.isEmpty {
                onMessageEdited?(editRoomJID, editMessageId, newText)
                return
            }
        }

        // Match TypeScript: const { data, id, body, ...rest } = await getDataFromXml(stanza);
        guard let messageData = MessageParser.getDataFromStanza(stanza) else {
            return
        }
        
        // Match TypeScript: if (!data) { console.log('No data in stanza'); return; }
        guard !messageData.dataAttrs.isEmpty else {
            return
        }
        
        // Match TypeScript: const message = await createMessageFromXml({ data, id, body, ...rest });
        let message = MessageParser.createMessageFromData(messageData)
        
        // Match TypeScript: store.dispatch(addRoomMessage({ roomJID: stanza.attrs.from, message }))
        let roomJIDForMessage = stanza.attributes["from"] ?? ""
        onHistoryMessageReceived?(message, roomJIDForMessage)
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
        let messageId = reactions.attributes["id"] ?? ""
        let reactionsList = reactions.children.compactMap { $0.name }
        let from = stanza.attributes["from"] ?? ""
        let dataAttrs = reactions.attributes
        
        onReactionReceived?(roomJid, messageId, reactionsList, from, dataAttrs)
    }
    
    /// Handle reaction history (onReactionHistory from TypeScript)
    public func onReactionHistory(_ stanza: XMPPStanza) {
        // Similar to onReactionMessage but for history
        guard let result = stanza.getChild("result"),
              let forwarded = result.getChild("forwarded"),
              let message = forwarded.getChild("message"),
              let reactions = message.getChild("reactions"),
              let stanzaId = message.getChild("stanza-id") else {
            return
        }
        
        let roomJid = stanzaId.attributes["by"] ?? ""
        let messageId = reactions.attributes["id"] ?? ""
        let reactionsList = reactions.children.compactMap { $0.name }
        let from = message.attributes["from"] ?? ""
        let dataAttrs = reactions.attributes
        
        onReactionReceived?(roomJid, messageId, reactionsList, from, dataAttrs)
    }
    
    /// Handle delete message (onDeleteMessage from TypeScript)
    /// Matches TypeScript: deleted.attrs.id (NOT stanzaId.attrs.id!)
    public func onDeleteMessage(_ stanza: XMPPStanza) {
        guard let id = stanza.attributes["id"],
              id == "deleteMessageStanza",
              let deleted = stanza.getChild("delete"),
              let stanzaId = stanza.getChild("stanza-id") else {
            return
        }
        
        // CRITICAL: Get messageId from deleted.attributes["id"], NOT from stanzaId
        // This matches TypeScript: deleted.attrs.id
        let roomJID = stanzaId.attributes["by"] ?? ""
        let messageId = deleted.attributes["id"] ?? ""
        onMessageDeleted?(roomJID, messageId)
    }
    
    /// Handle edit message (onEditMessage from TypeScript)
    /// Matches TypeScript: replace.attrs.text (NOT body.text!)
    public func onEditMessage(_ stanza: XMPPStanza) {
        guard let id = stanza.attributes["id"],
              id.contains("edit-message"),
              let stanzaId = stanza.getChild("stanza-id"),
              let replace = stanza.getChild("replace") else {
            return
        }
        
        let roomJID = stanzaId.attributes["by"] ?? ""
        let messageId = replace.attributes["id"] ?? ""
        // CRITICAL: Get text from replace.attributes["text"], NOT from body.text
        // This matches TypeScript: replace.attrs.text
        let newText = replace.attributes["text"] ?? ""
        onMessageEdited?(roomJID, messageId, newText)
    }
    
    /// Handle composing (typing) indicator (handleComposing from TypeScript)
    public func handleComposing(_ stanza: XMPPStanza, currentUser: String) {
        let from = stanza.attributes["from"] ?? ""
        let roomJID = from.components(separatedBy: "/").first ?? ""
        
        let isComposing = stanza.getChild("composing") != nil
        let isPaused = stanza.getChild("paused") != nil
        
        // Extract composing users list (simplified)
        var composingList: [String] = []
        // In a real implementation, you'd track composing users per room
        if isComposing {
            let userWallet = from.components(separatedBy: "/").last ?? ""
            if !userWallet.isEmpty && userWallet != currentUser {
                composingList.append(userWallet)
            }
        }
        
        onComposingChanged?(roomJID, composingList, isComposing)
    }
    
    /// Handle presence in room (onPresenceInRoom from TypeScript)
    public func onPresenceInRoom(_ stanza: XMPPStanza) {
        // Match TypeScript: stanza.attrs.id === 'presenceInRoom' && !stanza.getChild('error')
        guard stanza.attributes["id"] == "presenceInRoom",
              stanza.getChild("error") == nil else {
            return
        }
        
        let from = stanza.attributes["from"] ?? ""
        let roomJID = from.components(separatedBy: "/").first ?? ""
        let role = stanza.getChild("x")?.getChild("item")?.attributes["role"] ?? ""
        onPresenceInRoom?(roomJID, role)
    }
    
    /// Handle chat invite (onChatInvite from TypeScript)
    public func onChatInvite(_ stanza: XMPPStanza, client: XMPPClient?) {
        let mucX = stanza.getChildren("x").first { x in
            x.attributes["xmlns"] == "http://jabber.org/protocol/muc#user" &&
            x.getChild("invite") != nil
        }
        
        guard mucX != nil else {
            return
        }
        
        let from = stanza.attributes["from"] ?? ""
        let roomJID = from.components(separatedBy: "/").first ?? ""
        onChatInvite?(roomJID)
    }
    
    /// Handle room kicked (onRoomKicked from TypeScript).
    ///
    /// Mirrors `ethora-chat-component/src/networking/stanzaHandlers.ts:562`:
    /// the server confirms removal from a room with a `<presence
    /// type="unavailable">` carrying status `110` (this user) **and** `321`
    /// (membership lost — fired by ejabberd both on explicit kick and on
    /// `DELETE /chats`). Any other `unavailable` presence is just another
    /// occupant leaving and must not delete the room locally.
    public func onRoomKicked(_ stanza: XMPPStanza) {
        guard stanza.attributes["type"] == "unavailable" else { return }
        guard let xElement = stanza.getChild("x") else { return }
        let statusCodes = xElement.getChildren("status").compactMap { $0.attributes["code"] }
        guard statusCodes.contains("110"), statusCodes.contains("321") else { return }

        let from = stanza.attributes["from"] ?? ""
        let roomJID = from.components(separatedBy: "/").first ?? ""
        guard !roomJID.isEmpty else { return }
        onRoomKicked?(roomJID)
    }
    
    /// Handle get chat rooms (onGetChatRooms from TypeScript)
    public func onGetChatRooms(_ stanza: XMPPStanza, client: XMPPClient?) {
        // Implementation for parsing room list
        // This is a simplified version
        var rooms: [RoomData] = []
        // Parse rooms from stanza...
        onGetChatRooms?(rooms)
    }
    
    /// Handle new room created (onNewRoomCreated from TypeScript)
    public func onNewRoomCreated(_ stanza: XMPPStanza, client: XMPPClient?) {
        let from = stanza.attributes["from"] ?? ""
        let roomJID = from.components(separatedBy: "/").first ?? ""
        onNewRoomCreated?(roomJID)
    }
    
    /// Handle get last message archive (onGetLastMessageArchive from TypeScript)
    public func onGetLastMessageArchive(_ stanza: XMPPStanza) {
        // Implementation for parsing archive info
        let from = stanza.attributes["from"] ?? ""
        let roomJID = from.components(separatedBy: "/").first ?? ""
        // Parse archive info...
        onGetLastMessageArchive?(roomJID, false, nil, nil)
    }
    
    /// Handle message error (onMessageError from TypeScript)
    public func onMessageError(_ stanza: XMPPStanza, client: XMPPClient?) {
        guard stanza.name == "message",
              stanza.attributes["type"] == "error" else {
            return
        }
        
        let from = stanza.attributes["from"] ?? ""
        let roomJID = from.components(separatedBy: "/").first ?? ""
        onMessageError?(roomJID)
    }
    
    /// Handle IQ error responses for get-history queries
    public func onIQError(_ stanza: XMPPStanza) {
        guard stanza.name == "iq",
              stanza.attributes["type"] == "error" else {
            return
        }
        
        let id = stanza.attributes["id"] ?? ""
        let from = stanza.attributes["from"] ?? ""
        
        if id.hasPrefix("get-history:") {
            let roomJID = from.components(separatedBy: "/").first ?? from
            
            var errorType = "unknown"
            var errorCondition = "unknown"
            var errorText = ""
            
            if let errorNode = stanza.getChild("error") {
                errorType = errorNode.attributes["type"] ?? "unknown"
                
                for child in errorNode.children {
                    if child.attributes["xmlns"]?.contains("xmpp-stanzas") == true {
                        errorCondition = child.name
                    }
                    if child.name == "text" {
                        errorText = child.text ?? ""
                    }
                }
            }
            
            NotificationCenter.default.post(
                name: NSNotification.Name("XMPPHistoryLoadFailed"),
                object: nil,
                userInfo: [
                    "roomJID": roomJID,
                    "queryId": id,
                    "errorType": errorType,
                    "errorCondition": errorCondition,
                    "errorText": errorText
                ]
            )
        }
    }
    
    /// Handle get room info (onGetRoomInfo from TypeScript)
    public func onGetRoomInfo(_ stanza: XMPPStanza) {
        // Implementation for parsing room info
    }
    
    /// Register a get-history collector
    public func registerGetHistoryCollector(queryId: String, roomJID: String, collector: @escaping (XMPPStanza, String) -> Void) {
        getHistoryCollectors[queryId] = collector
    }
    
    /// Unregister a get-history collector
    public func unregisterGetHistoryCollector(queryId: String) {
        getHistoryCollectors.removeValue(forKey: queryId)
    }
}
