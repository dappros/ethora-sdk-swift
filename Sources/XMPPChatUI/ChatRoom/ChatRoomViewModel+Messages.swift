//
//  ChatRoomViewModel+Messages.swift
//  XMPPChatUI
//

import Foundation
import XMPPChatCore

extension ChatRoomViewModel {
    public func handleIncomingMessage(_ message: Message) {
        // Strict delivery confirmation policy:
        // Mark message as sent ONLY when message is not optimistic and has server origin.
        let hasServerOrigin = !(message.xmppFrom ?? "").isEmpty
        let isServerConfirmedMessage = (message.pending != true) && hasServerOrigin

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔵 ChatRoomViewModel.handleIncomingMessage: START")
        print("   Message ID: '\(message.id)'")
        print("   Message body: '\(message.body)'")
        print("   Message body.isEmpty: \(message.body.isEmpty)")
        print("   Message body.count: \(message.body.count)")
        print("   Message xmppId: '\(message.xmppId ?? "nil")'")
        print("   Message timestamp: \(message.timestamp?.description ?? "nil")")
        print("   Message roomJid: '\(message.roomJid)'")
        print("   Message user.id: '\(message.user.id)'")
        print("   Message pending: \(message.pending)")
        print("   Current room.jid: '\(room.jid)'")
        print("   Current messages.count: \(messages.count)")
        print("   isLoadingMore: \(isLoadingMore)")
        print("   isLoading: \(isLoading)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        // Clear any errors when we successfully receive a message
        if loadError != nil {
            loadError = nil
        }
        
        // CRITICAL: Allow empty body for media messages or system messages
        let hasBody = !message.body.isEmpty
        let isMediaMessage = message.isMediafile == "true" || message.mimetype != nil
        let isSystemMessage = message.isSystemMessage == "true" || message.isSystemMessage == "1"
        
        print("🔍 ChatRoomViewModel.handleIncomingMessage: Body check")
        print("   hasBody: \(hasBody)")
        print("   isMediaMessage: \(isMediaMessage)")
        print("   isSystemMessage: \(isSystemMessage)")
        print("   body.isEmpty: \(message.body.isEmpty)")
        print("   body: '\(message.body)'")
        
        guard hasBody || isMediaMessage || isSystemMessage else {
            print("❌ ChatRoomViewModel.handleIncomingMessage: SKIPPED - message body is empty and not media/system")
            print("   Message ID: '\(message.id)'")
            print("   Message has media: \(message.isMediafile == "true")")
            print("   Message mimetype: '\(message.mimetype ?? "nil")'")
            print("   Message isSystemMessage: \(message.isSystemMessage)")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            return
        }
        
        if !hasBody && (isMediaMessage || isSystemMessage) {
            print("✅ ChatRoomViewModel.handleIncomingMessage: Allowing message with empty body (media/system message)")
        }
        
        print("✅ ChatRoomViewModel.handleIncomingMessage: Message body check passed")
        
        let messageRoomBareJID = message.roomJid.components(separatedBy: "/").first ?? message.roomJid
        let currentRoomBareJID = room.jid.components(separatedBy: "/").first ?? room.jid
        
        print("🔍 ChatRoomViewModel.handleIncomingMessage: Checking room match")
        print("   messageRoomBareJID: '\(messageRoomBareJID)'")
        print("   currentRoomBareJID: '\(currentRoomBareJID)'")
        print("   Match: \(messageRoomBareJID == currentRoomBareJID)")
        
        guard messageRoomBareJID == currentRoomBareJID else {
            // Message is for a different room, ignore it
            print("❌ ChatRoomViewModel.handleIncomingMessage: SKIPPED - Message is for different room")
            print("   Message room: '\(messageRoomBareJID)'")
            print("   Current room: '\(currentRoomBareJID)'")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            return
        }
        
        print("✅ ChatRoomViewModel.handleIncomingMessage: Room matches, processing message")
        print("📥 ChatRoomViewModel.handleIncomingMessage: Received message with id: '\(message.id)', body: '\(message.body.prefix(50))', xmppId: '\(message.xmppId ?? "nil")'")
        print("   Current messages count: \(messages.count)")
        print("   isLoadingMore: \(isLoadingMore)")
        
        // Check if message already exists in array
        print("🔍 ChatRoomViewModel.handleIncomingMessage: Checking for existing message with matching ID")
        let existingMessageIndices = messages.enumerated().compactMap { index, msg -> (Int, String)? in
            let matches = msg.id == message.id ||
                (message.xmppId != nil && msg.id == message.xmppId) ||
                (msg.xmppId != nil && msg.xmppId == message.id) ||
                (msg.xmppId != nil && message.xmppId != nil && msg.xmppId == message.xmppId)
            if matches {
                return (index, msg.id)
            }
            return nil
        }
        
        if !existingMessageIndices.isEmpty {
            print("🔍 ChatRoomViewModel.handleIncomingMessage: Found \(existingMessageIndices.count) existing message(s) with matching ID:")
            for (index, msgId) in existingMessageIndices {
                let existingMsg = messages[index]
                print("   Index \(index): ID='\(msgId)', body='\(existingMsg.body.prefix(30))', pending=\(existingMsg.pending)")
            }
        } else {
            print("✅ ChatRoomViewModel.handleIncomingMessage: No existing message found with matching ID - will add as new")
        }
        
        if let existingIndex = messages.firstIndex(where: { msg in
            msg.id == message.id ||
            (message.xmppId != nil && msg.id == message.xmppId) ||
            (msg.xmppId != nil && msg.xmppId == message.id) ||
            (msg.xmppId != nil && message.xmppId != nil && msg.xmppId == message.xmppId)
        }) {
            print("🔍 ChatRoomViewModel.handleIncomingMessage: Found existing message at index \(existingIndex)")
            let existingMessage = messages[existingIndex]
            
            if isLoadingMore {
                let isPendingMessage = existingMessage.pending == true
                
                if !isPendingMessage {
                    print("⚠️ ChatRoomViewModel.handleIncomingMessage: Message already exists during history load (not pending), skipping duplicate")
                    print("   Message ID: '\(message.id)', timestamp: \(message.timestamp?.description ?? "nil")")
                    print("   Existing message at index \(existingIndex): body='\(existingMessage.body.prefix(30))', pending=\(existingMessage.pending)")
                    print("   Incoming message: body='\(message.body.prefix(30))', pending=\(message.pending)")
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    
                    if isLoadingMore {
                        historyLoadReceivedCount += 1
                        let timeSinceStart = historyLoadStartTime.map { Date().timeIntervalSince($0) } ?? 0
                        
                        let oldestMessageTimestamp = messages.first(where: { $0.id != "delimiter-new" })?.timestamp ?? Int64.max
                        let incomingTimestamp = message.timestamp ?? 0
                        let isOlderThanOldest = incomingTimestamp < oldestMessageTimestamp
                        
                        if isOlderThanOldest {
                            print("📜 ChatRoomViewModel.handleIncomingMessage: Duplicate message is older than oldest (\(incomingTimestamp) < \(oldestMessageTimestamp)) - may need to request even older messages")
                        }
                        
                        if historyLoadReceivedCount >= pageSize || timeSinceStart >= 2.0 {
                            isLoadingMore = false
                            scrollPositionBeforeLoad = nil
                            let receivedCount = historyLoadReceivedCount
                            historyLoadReceivedCount = 0
                            historyLoadStartTime = nil
                            print("✅ ChatRoomViewModel.handleIncomingMessage: Reset isLoadingMore after receiving \(receivedCount) messages (including duplicates) during history load")
                        } else {
                            loadingMoreTask?.cancel()
                            loadingMoreTask = Task {
                                try? await Task.sleep(nanoseconds: 1_000_000_000)
                                if isLoadingMore {
                                    isLoadingMore = false
                                    scrollPositionBeforeLoad = nil
                                    let receivedCount = historyLoadReceivedCount
                                    historyLoadReceivedCount = 0
                                    historyLoadStartTime = nil
                                    print("✅ ChatRoomViewModel.handleIncomingMessage: Reset isLoadingMore after 1s silence during history load (received \(receivedCount) messages)")
                                }
                            }
                        }
                    }
                    
                    return
                } else {
                    print("✅ ChatRoomViewModel.handleIncomingMessage: Updating pending message confirmation during history load")
                }
            }
            
            let updatedMessage = Message(
                id: message.id,
                user: message.user,
                date: message.date,
                body: message.body,
                roomJid: message.roomJid,
                key: message.key ?? existingMessage.key,
                coinsInMessage: message.coinsInMessage ?? existingMessage.coinsInMessage,
                numberOfReplies: message.numberOfReplies ?? existingMessage.numberOfReplies,
                isSystemMessage: message.isSystemMessage ?? existingMessage.isSystemMessage,
                isMediafile: message.isMediafile ?? existingMessage.isMediafile,
                locationPreview: message.locationPreview ?? existingMessage.locationPreview,
                mimetype: message.mimetype ?? existingMessage.mimetype,
                location: message.location ?? existingMessage.location,
                pending: isServerConfirmedMessage ? false : existingMessage.pending,
                timestamp: message.timestamp ?? existingMessage.timestamp,
                showInChannel: message.showInChannel ?? existingMessage.showInChannel,
                activeMessage: message.activeMessage ?? existingMessage.activeMessage,
                isReply: message.isReply ?? existingMessage.isReply,
                isDeleted: message.isDeleted ?? existingMessage.isDeleted,
                mainMessage: message.mainMessage ?? existingMessage.mainMessage,
                reply: message.reply ?? existingMessage.reply,
                reaction: message.reaction ?? existingMessage.reaction,
                fileName: message.fileName ?? existingMessage.fileName,
                translations: message.translations ?? existingMessage.translations,
                langSource: message.langSource ?? existingMessage.langSource,
                originalName: message.originalName ?? existingMessage.originalName,
                size: message.size ?? existingMessage.size,
                xmppId: message.xmppId ?? existingMessage.xmppId,
                xmppFrom: message.xmppFrom ?? existingMessage.xmppFrom,
                waveForm: message.waveForm ?? existingMessage.waveForm
            )
            
            let oldBody = existingMessage.body
            messages[existingIndex] = updatedMessage
            room.messages = messages
            
            print("🔄 ChatRoomViewModel.handleIncomingMessage: Updated existing message at index \(existingIndex)")
            print("   Old body: '\(oldBody.prefix(50))'")
            print("   New body: '\(updatedMessage.body.prefix(50))'")
            print("   Total messages after update: \(messages.count)")
            
            MessageCache.shared.saveMessages(messages, forRoomJID: room.jid)
            print("💾 ChatRoomViewModel.handleIncomingMessage: Saved updated message to cache")
            
            return
        }
        
        print("✅ ChatRoomViewModel.handleIncomingMessage: No exact ID match found - checking for edit or pending messages")
        
        if let editedIndex = messages.firstIndex(where: { msg in
            msg.id == message.id && msg.body != message.body
        }) {
            print("🔄 ChatRoomViewModel.handleIncomingMessage: Processing edit confirmation at index \(editedIndex)")
            print("   Existing body: '\(messages[editedIndex].body.prefix(50))'")
            print("   New body: '\(message.body.prefix(50))'")
            
            let existingMessage = messages[editedIndex]
            let updatedMessage = Message(
                id: message.id,
                user: message.user,
                date: message.date,
                body: message.body,
                roomJid: message.roomJid,
                key: message.key ?? existingMessage.key,
                coinsInMessage: message.coinsInMessage ?? existingMessage.coinsInMessage,
                numberOfReplies: message.numberOfReplies ?? existingMessage.numberOfReplies,
                isSystemMessage: message.isSystemMessage ?? existingMessage.isSystemMessage,
                isMediafile: message.isMediafile ?? existingMessage.isMediafile,
                locationPreview: message.locationPreview ?? existingMessage.locationPreview,
                mimetype: message.mimetype ?? existingMessage.mimetype,
                location: message.location ?? existingMessage.location,
                pending: false,
                timestamp: message.timestamp ?? existingMessage.timestamp,
                showInChannel: message.showInChannel ?? existingMessage.showInChannel,
                activeMessage: message.activeMessage ?? existingMessage.activeMessage,
                isReply: message.isReply ?? existingMessage.isReply,
                isDeleted: message.isDeleted ?? existingMessage.isDeleted,
                mainMessage: message.mainMessage ?? existingMessage.mainMessage,
                reply: message.reply ?? existingMessage.reply,
                reaction: message.reaction ?? existingMessage.reaction,
                fileName: message.fileName ?? existingMessage.fileName,
                translations: message.translations ?? existingMessage.translations,
                langSource: message.langSource ?? existingMessage.langSource,
                originalName: message.originalName ?? existingMessage.originalName,
                size: message.size ?? existingMessage.size,
                xmppId: message.xmppId ?? existingMessage.xmppId,
                xmppFrom: message.xmppFrom ?? existingMessage.xmppFrom,
                waveForm: message.waveForm ?? existingMessage.waveForm
            )
            
            messages[editedIndex] = updatedMessage
            room.messages = messages
            
            print("✅ ChatRoomViewModel.handleIncomingMessage: Updated message as edit confirmation")
            print("   Total messages after edit update: \(messages.count)")
            
            MessageCache.shared.saveMessages(messages, forRoomJID: room.jid)
            print("💾 ChatRoomViewModel.handleIncomingMessage: Saved edited message to cache")
            
            return
        }
        
        print("🔍 ChatRoomViewModel.handleIncomingMessage: Checking if message is from current user")
        
        let isFromCurrentUser = message.user.id == currentUserId || 
                                message.user.xmppUsername == currentUserId ||
                                (message.xmppFrom != nil && (message.xmppFrom?.contains(currentUserId) == true || 
                                                              message.xmppFrom?.contains(message.user.xmppUsername ?? "") == true))
        
        print("   isFromCurrentUser: \(isFromCurrentUser)")
        
        if isFromCurrentUser {
            print("🔍 ChatRoomViewModel.handleIncomingMessage: Strict mode ON - no pending match by body")
        }
        
        let shouldInsertDelimiter = !messages.contains(where: { $0.id == "delimiter-new" }) &&
                                    room.lastViewedTimestamp != nil &&
                                    room.lastViewedTimestamp! > 0 &&
                                    (message.timestamp ?? 0) > room.lastViewedTimestamp!
        
        if shouldInsertDelimiter {
            if let delimiterIndex = messages.firstIndex(where: { ($0.timestamp ?? 0) > room.lastViewedTimestamp! }) {
                let delimiterMessage = Message(
                    id: "delimiter-new",
                    user: User(
                        id: "system",
                        name: "System",
                        firstName: nil,
                        lastName: nil,
                        profileImage: nil,
                        xmppUsername: "system"
                    ),
                    date: Date(),
                    body: "New Messages",
                    roomJid: room.jid,
                    timestamp: room.lastViewedTimestamp
                )
                messages.insert(delimiterMessage, at: delimiterIndex)
            }
        }
        
        print("🔍 ChatRoomViewModel.handleIncomingMessage: Final duplicate check before adding")
        
        let duplicateCheckMessages = messages.filter { msg in
            msg.id == message.id ||
            (message.xmppId != nil && msg.id == message.xmppId) ||
            (msg.xmppId != nil && msg.xmppId == message.id) ||
            (msg.xmppId != nil && message.xmppId != nil && msg.xmppId == message.xmppId)
        }
        
        let alreadyExists = !isLoadingMore && !duplicateCheckMessages.isEmpty
        
        if alreadyExists {
            print("⚠️ ChatRoomViewModel.handleIncomingMessage: Message already exists in final check, skipping duplicate")
            
            if let existingIndex = messages.firstIndex(where: { $0.id == message.id && $0.body != message.body }) {
                let existingMessage = messages[existingIndex]
                let updatedMessage = Message(
                    id: message.id,
                    user: message.user,
                    date: message.date,
                    body: message.body,
                    roomJid: message.roomJid,
                    key: message.key ?? existingMessage.key,
                    coinsInMessage: message.coinsInMessage ?? existingMessage.coinsInMessage,
                    numberOfReplies: message.numberOfReplies ?? existingMessage.numberOfReplies,
                    isSystemMessage: message.isSystemMessage ?? existingMessage.isSystemMessage,
                    isMediafile: message.isMediafile ?? existingMessage.isMediafile,
                    locationPreview: message.locationPreview ?? existingMessage.locationPreview,
                    mimetype: message.mimetype ?? existingMessage.mimetype,
                    location: message.location ?? existingMessage.location,
                    pending: isServerConfirmedMessage ? false : existingMessage.pending,
                    timestamp: message.timestamp ?? existingMessage.timestamp,
                    showInChannel: message.showInChannel ?? existingMessage.showInChannel,
                    activeMessage: message.activeMessage ?? existingMessage.activeMessage,
                    isReply: message.isReply ?? existingMessage.isReply,
                    isDeleted: message.isDeleted ?? existingMessage.isDeleted,
                    mainMessage: message.mainMessage ?? existingMessage.mainMessage,
                    reply: message.reply ?? existingMessage.reply,
                    reaction: message.reaction ?? existingMessage.reaction,
                    fileName: message.fileName ?? existingMessage.fileName,
                    translations: message.translations ?? existingMessage.translations,
                    langSource: message.langSource ?? existingMessage.langSource,
                    originalName: message.originalName ?? existingMessage.originalName,
                    size: message.size ?? existingMessage.size,
                    xmppId: message.xmppId ?? existingMessage.xmppId,
                    xmppFrom: message.xmppFrom ?? existingMessage.xmppFrom,
                    waveForm: message.waveForm ?? existingMessage.waveForm
                )
                messages[existingIndex] = updatedMessage
                room.messages = messages
                MessageCache.shared.saveMessages(messages, forRoomJID: room.jid)
                return
            }
            return
        }
        
        let messageCountBeforeAdd = messages.count
        messages.append(message)
        
        if loadError != nil {
            loadError = nil
        }
        
        if isRefreshing {
            if let lastMessageId = messages.last?.id, lastMessageId != lastMessageIdBeforeRefresh {
                isRefreshing = false
                lastMessageIdBeforeRefresh = nil
            } else if messageCountBeforeAdd == 0 && messages.count > 0 {
                isRefreshing = false
                lastMessageIdBeforeRefresh = nil
            }
        }
        
        messages.sort { msg1, msg2 in
            let ts1 = msg1.timestamp ?? 0
            let ts2 = msg2.timestamp ?? 0
            return ts1 < ts2
        }
        
        var seenIds = Set<String>()
        messages = messages.filter { msg in
            let id = msg.id
            if seenIds.contains(id) {
                return false
            }
            seenIds.insert(id)
            return true
        }
        
        room.messages = messages
        self.room = room
        
        MessageCache.shared.saveMessages(messages, forRoomJID: room.jid)
        MessageCache.shared.cleanupIfNeeded()
        
        if isLoading && expectedMessageCount > 0 {
            receivedMessageCount += 1
            let timeSinceStart = loadingStartTime.map { Date().timeIntervalSince($0) } ?? 0
            
            if receivedMessageCount >= expectedMessageCount || timeSinceStart >= 3.0 {
                isLoading = false
                messagesLoaded = true
                loadingStartTime = nil
                
                if receivedMessageCount > 0 {
                    loadError = nil
                }
            }
        } else if isLoadingMore {
            historyLoadReceivedCount += 1
            let timeSinceStart = historyLoadStartTime.map { Date().timeIntervalSince($0) } ?? 0
            
            if historyLoadReceivedCount >= pageSize || timeSinceStart >= 2.0 {
                isLoadingMore = false
                scrollPositionBeforeLoad = nil
                historyLoadReceivedCount = 0
                historyLoadStartTime = nil
                
                let currentCount = messages.count
                let loadedCount = currentCount - messagesCountBeforeLoad
                
                NotificationCenter.default.post(
                    name: NSNotification.Name("MessagesLoaded"),
                    object: nil,
                    userInfo: [
                        "oldCount": messagesCountBeforeLoad,
                        "newCount": currentCount,
                        "loadedCount": loadedCount
                    ]
                )
            } else {
                loadingMoreTask?.cancel()
                loadingMoreTask = Task {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if isLoadingMore {
                        isLoadingMore = false
                        scrollPositionBeforeLoad = nil
                        historyLoadReceivedCount = 0
                        historyLoadStartTime = nil
                        
                        let currentCount = messages.count
                        let loadedCount = currentCount - messagesCountBeforeLoad
                        
                        NotificationCenter.default.post(
                            name: NSNotification.Name("MessagesLoaded"),
                            object: nil,
                            userInfo: [
                                "oldCount": messagesCountBeforeLoad,
                                "newCount": currentCount,
                                "loadedCount": loadedCount
                            ]
                        )
                    }
                }
            }
        }
        
        if !messagesLoaded {
            messagesLoaded = true
        }
        
        onMessagesUpdated?(room)
        
        NotificationCenter.default.post(
            name: NSNotification.Name("RoomMessagesUpdated"),
            object: nil,
            userInfo: [
                "roomJID": room.jid,
                "messageCount": messages.count
            ]
        )
    }
}
