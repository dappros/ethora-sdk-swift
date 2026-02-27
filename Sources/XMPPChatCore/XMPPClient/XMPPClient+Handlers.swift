//
//  XMPPClient+Handlers.swift
//  XMPPChatCore
//

import Foundation

extension XMPPClient {
    internal func handleStanza(_ stanza: XMPPStanza) {
        // Initialize handlers if needed
        if stanzaHandlers == nil {
            stanzaHandlers = StanzaHandlers(client: self)
            setupStanzaHandlers()
        }
        
        // Initialize HandleStanzas router if needed
        if handleStanzas == nil {
            handleStanzas = HandleStanzas(client: self, stanzaHandlers: stanzaHandlers!)
        }
        
        // Route stanza through HandleStanzas (matches TypeScript handleStanza function)
        handleStanzas?.handleStanza(stanza)
    }
    
    /// Process incoming message (save to cache, post notification for RoomListViewModel)
    internal func processIncomingMessage(_ message: Message) {
        let roomJID = message.roomJid.components(separatedBy: "/").first ?? message.roomJid
        
        print("💾 XMPPClient.processIncomingMessage: Processing message for cache and room list")
        
        // MessageCache is @MainActor, so we need to call it from main actor context
        Task { @MainActor in
            // Load existing messages from cache
            var cachedMessages = MessageCache.shared.loadMessages(forRoomJID: roomJID) ?? []
            
            // Check if message already exists (avoid duplicates)
            if !cachedMessages.contains(where: { $0.id == message.id || ($0.xmppId != nil && $0.xmppId == message.id) || (message.xmppId != nil && $0.id == message.xmppId) }) {
                print("   ✅ Message is new, adding to cache")
                
                // Add message to cache
                cachedMessages.append(message)
                
                // Sort by timestamp
                cachedMessages.sort { msg1, msg2 in
                    let ts1 = msg1.timestamp ?? 0
                    let ts2 = msg2.timestamp ?? 0
                    return ts1 < ts2
                }
                
                // Save to cache (limit to 100 messages per room)
                let messagesToSave = Array(cachedMessages.suffix(100))
                MessageCache.shared.saveMessages(messagesToSave, forRoomJID: roomJID)
                
                // Post notification for RoomListViewModel to update room.messages
                NotificationCenter.default.post(
                    name: NSNotification.Name("RoomMessagesUpdated"),
                    object: self,
                    userInfo: [
                        "roomJID": roomJID,
                        "messageCount": messagesToSave.count,
                        "message": message
                    ]
                )
            } else {
                print("   ⚠️ Message already exists in cache, skipping")
            }
        }
    }
    
    internal func setupStanzaHandlers() {
        guard let handlers = stanzaHandlers else { return }
        
        // Set up real-time message handler
        handlers.onMessageReceived = { [weak self] (message: Message, roomJID: String) in
            guard let self = self else { return }
            
            // CRITICAL: Process message for cache and room list update
            if !message.body.isEmpty || message.isMediafile == "true" || message.isSystemMessage == "true" || message.isSystemMessage == "1" {
                self.processIncomingMessage(message)
            }
            
            // Notify delegate
            self.delegate?.xmppClient(self, didReceiveMessage: message)
            
            // Post notification
            NotificationCenter.default.post(
                name: NSNotification.Name("XMPPMessageReceived"),
                object: self,
                userInfo: [
                    "message": message,
                    "roomJID": roomJID
                ]
            )
        }
        
        // Set up history message handler
        handlers.onHistoryMessageReceived = { [weak self] (message: Message, roomJID: String) in
            guard let self = self else { return }
            
            // Process incoming message
            self.processIncomingMessage(message)
            
            // Notify delegate
            self.delegate?.xmppClient(self, didReceiveMessage: message)
        }
        
        // Set up reaction handler
        handlers.onReactionReceived = { [weak self] (roomJID: String, messageId: String, reactions: [String], from: String, data: [String: String]) in
            guard let self = self else { return }
            
            // Update RoomStore
            Task { @MainActor in
                RoomStore.shared.setReactions(
                    roomJID: roomJID,
                    messageId: messageId,
                    reactions: reactions,
                    from: from,
                    data: data
                )
            }
            
            // Post notification
            NotificationCenter.default.post(
                name: NSNotification.Name("XMPPReactionReceived"),
                object: self,
                userInfo: [
                    "roomJID": roomJID,
                    "messageId": messageId,
                    "reactions": reactions,
                    "from": from,
                    "data": data
                ]
            )
        }
        
        // Set up composing (typing) indicator handler
        handlers.onComposingChanged = { [weak self] (roomJID: String, composingList: [String], isComposing: Bool) in
            guard let self = self else { return }
            
            // Post notification
            NotificationCenter.default.post(
                name: NSNotification.Name("XMPPComposingChanged"),
                object: self,
                userInfo: [
                    "roomJID": roomJID,
                    "composingList": composingList,
                    "isComposing": isComposing
                ]
            )
        }
        
        // Set up delete message handler
        handlers.onMessageDeleted = { [weak self] (roomJID: String, messageId: String) in
            guard let self = self else { return }
            
            // Update RoomStore
            Task { @MainActor in
                RoomStore.shared.deleteMessage(roomJID: roomJID, messageId: messageId)
            }
            
            // Post notification
            NotificationCenter.default.post(
                name: NSNotification.Name("XMPPMessageDeleted"),
                object: self,
                userInfo: [
                    "roomJID": roomJID,
                    "messageId": messageId
                ]
            )
        }
        
        // Set up edit message handler
        handlers.onMessageEdited = { [weak self] (roomJID: String, messageId: String, newText: String) in
            guard let self = self else { return }
            
            // Update RoomStore
            Task { @MainActor in
                var updates = PartialMessageUpdate()
                updates.body = newText
                RoomStore.shared.updateMessage(
                    roomJID: roomJID,
                    messageId: messageId,
                    updates: updates
                )
            }
            
            // Post notification
            NotificationCenter.default.post(
                name: NSNotification.Name("XMPPMessageEdited"),
                object: self,
                userInfo: [
                    "roomJID": roomJID,
                    "messageId": messageId,
                    "newText": newText
                ]
            )
        }
    }
}
