//
//  ChatRoomViewModel+Observers.swift
//  XMPPChatUI
//

import Foundation
import XMPPChatCore

extension ChatRoomViewModel {
    internal func setupObservers() {
        // Observe composing (typing indicator) notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleComposingNotification(_:)),
            name: NSNotification.Name("XMPPComposingChanged"),
            object: nil
        )
        
        // Observe history complete notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHistoryCompleteNotification(_:)),
            name: NSNotification.Name("XMPPHistoryComplete"),
            object: nil
        )
        
        // Observe reaction notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleReactionNotification(_:)),
            name: NSNotification.Name("XMPPReactionReceived"),
            object: nil
        )
        
        // Observe delete message notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeleteNotification(_:)),
            name: NSNotification.Name("XMPPMessageDeleted"),
            object: nil
        )
        
        // Observe edit message notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEditNotification(_:)),
            name: NSNotification.Name("XMPPMessageEdited"),
            object: nil
        )
        
        // Observe incoming real-time messages via NotificationCenter
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleIncomingMessageNotification(_:)),
            name: NSNotification.Name("XMPPMessageReceived"),
            object: nil
        )
        
        // Observe history load failures for retry logic
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHistoryLoadFailedNotification(_:)),
            name: NSNotification.Name("XMPPHistoryLoadFailed"),
            object: nil
        )
    }
    
    // MARK: - History Load Failure Handler
    
    @objc internal func handleHistoryLoadFailedNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let roomJID = userInfo["roomJID"] as? String else {
            return
        }
        
        let normalizedFailedRoom = roomJID.components(separatedBy: "/").first ?? roomJID
        let normalizedCurrentRoom = room.jid.components(separatedBy: "/").first ?? room.jid
        
        guard normalizedFailedRoom == normalizedCurrentRoom else {
            return
        }
        
        Task { @MainActor in
            isLoading = false
            isRefreshing = false
            
            if let errorCondition = userInfo["errorCondition"] as? String {
                switch errorCondition {
                case "not-allowed":
                    loadError = "You don't have permission to view this chat's history."
                case "item-not-found":
                    loadError = "Chat history not found."
                case "forbidden":
                    loadError = "Access to chat history is forbidden."
                case "feature-not-implemented":
                    loadError = "Message history is not available for this chat."
                default:
                    loadError = "Failed to load messages. Pull down to retry."
                }
            } else if let errorText = userInfo["errorText"] as? String, !errorText.isEmpty {
                loadError = errorText
            } else {
                loadError = "Failed to load messages. Pull down to retry."
            }
            
            scheduleHistoryRetry()
        }
    }
    
    // MARK: - Retry Logic
    
    internal func scheduleHistoryRetry() {
        guard historyRetryAttempts < maxHistoryRetryAttempts else {
            return
        }
        
        historyRetryAttempts += 1
        let delay = Double(historyRetryAttempts) * 2.0
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            
            if messages.isEmpty && client.isFullyConnected() {
                loadError = nil
                loadMessages(forceReload: true)
            }
        }
    }
    
    internal func resetHistoryRetry() {
        historyRetryAttempts = 0
    }
    
    @objc internal func handleIncomingMessageNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let message = userInfo["message"] as? Message else {
            return
        }
        
        let normalizedMessageRoom = message.roomJid.components(separatedBy: "/").first ?? message.roomJid
        let normalizedCurrentRoom = room.jid.components(separatedBy: "/").first ?? room.jid
        
        guard normalizedMessageRoom == normalizedCurrentRoom else {
            return
        }
        
        handleIncomingMessage(message)
    }
    
    @objc internal func handleComposingNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let notificationRoomJID = userInfo["roomJID"] as? String,
              let composingList = userInfo["composingList"] as? [String],
              let isComposing = userInfo["isComposing"] as? Bool else {
            return
        }
        
        let normalizedNotificationRoom = notificationRoomJID.components(separatedBy: "/").first ?? notificationRoomJID
        let normalizedCurrentRoom = room.jid.components(separatedBy: "/").first ?? room.jid
        
        guard normalizedNotificationRoom == normalizedCurrentRoom else {
            return
        }
        
        let filteredComposingList = composingList.filter { userId in
            let normalizedUserId = userId.lowercased().trimmingCharacters(in: .whitespaces)
            let normalizedCurrentId = currentUserId.lowercased().trimmingCharacters(in: .whitespaces)
            
            if let currentXmpp = currentUserXmppUsername {
                let normalizedCurrentXmpp = currentXmpp.lowercased().trimmingCharacters(in: .whitespaces)
                let normalizedUserXmpp = userId.lowercased().trimmingCharacters(in: .whitespaces)
                if normalizedUserXmpp == normalizedCurrentXmpp {
                    return false
                }
            }
            
            return normalizedUserId != normalizedCurrentId
        }
        
        Task { @MainActor in
            self.isTyping = !filteredComposingList.isEmpty
            self.composingUsers = filteredComposingList
        }
    }
    
    @objc internal func handleHistoryCompleteNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let notificationRoomJID = userInfo["roomJID"] as? String,
              let historyComplete = userInfo["historyComplete"] as? Bool else {
            return
        }
        
        let normalizedNotificationRoom = notificationRoomJID.components(separatedBy: "/").first ?? notificationRoomJID
        let normalizedCurrentRoom = room.jid.components(separatedBy: "/").first ?? room.jid
        
        guard normalizedNotificationRoom == normalizedCurrentRoom else {
            return
        }
        
        Task { @MainActor in
            if loadError != nil && !messages.isEmpty {
                loadError = nil
            }
            
            resetHistoryRetry()
            
            self.room.historyComplete = historyComplete
        }
    }
    
    @objc internal func handleReactionNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let notificationRoomJID = userInfo["roomJID"] as? String,
              let messageId = userInfo["messageId"] as? String,
              let reactions = userInfo["reactions"] as? [String],
              let from = userInfo["from"] as? String,
              let data = userInfo["data"] as? [String: String] else {
            return
        }
        
        let normalizedNotificationRoom = notificationRoomJID.components(separatedBy: "/").first ?? notificationRoomJID
        let normalizedCurrentRoom = room.jid.components(separatedBy: "/").first ?? room.jid
        
        guard normalizedNotificationRoom == normalizedCurrentRoom else {
            return
        }
        
        Task { @MainActor in
            if let index = messages.firstIndex(where: { $0.id == messageId }) {
                var updatedMessage = messages[index]
                if updatedMessage.reaction == nil {
                    updatedMessage.reaction = [:]
                }
                let fromId = from.components(separatedBy: "@").first ?? from
                if reactions.isEmpty {
                    updatedMessage.reaction?.removeValue(forKey: fromId)
                } else {
                    updatedMessage.reaction?[fromId] = ReactionMessage(emoji: reactions, data: data)
                }
                messages[index] = updatedMessage
                room.messages = messages
                
                MessageCache.shared.saveMessages(messages, forRoomJID: room.jid)
            }
        }
    }
    
    @objc internal func handleDeleteNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let notificationRoomJID = userInfo["roomJID"] as? String,
              let messageId = userInfo["messageId"] as? String else {
            return
        }
        
        let normalizedNotificationRoom = notificationRoomJID.components(separatedBy: "/").first ?? notificationRoomJID
        let normalizedCurrentRoom = room.jid.components(separatedBy: "/").first ?? room.jid
        
        guard normalizedNotificationRoom == normalizedCurrentRoom else {
            return
        }
        
        Task { @MainActor in
            messages = messages.filter { $0.id != messageId }
            room.messages = messages
            
            MessageCache.shared.saveMessages(messages, forRoomJID: room.jid)
        }
    }
    
    @objc internal func handleEditNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let notificationRoomJID = userInfo["roomJID"] as? String,
              let messageId = userInfo["messageId"] as? String,
              let newText = userInfo["newText"] as? String else {
            return
        }
        
        let normalizedNotificationRoom = notificationRoomJID.components(separatedBy: "/").first ?? notificationRoomJID
        let normalizedCurrentRoom = room.jid.components(separatedBy: "/").first ?? room.jid
        
        guard normalizedNotificationRoom == normalizedCurrentRoom else {
            return
        }
        
        Task { @MainActor in
            if let index = messages.firstIndex(where: { $0.id == messageId }) {
                var updatedMessage = messages[index]
                let editedMessage = Message(
                    id: updatedMessage.id,
                    user: updatedMessage.user,
                    date: updatedMessage.date,
                    body: newText,
                    roomJid: updatedMessage.roomJid,
                    key: updatedMessage.key,
                    coinsInMessage: updatedMessage.coinsInMessage,
                    numberOfReplies: updatedMessage.numberOfReplies,
                    isSystemMessage: updatedMessage.isSystemMessage,
                    isMediafile: updatedMessage.isMediafile,
                    locationPreview: updatedMessage.locationPreview,
                    mimetype: updatedMessage.mimetype,
                    location: updatedMessage.location,
                    pending: updatedMessage.pending,
                    timestamp: updatedMessage.timestamp,
                    showInChannel: updatedMessage.showInChannel,
                    activeMessage: updatedMessage.activeMessage,
                    isReply: updatedMessage.isReply,
                    isDeleted: updatedMessage.isDeleted,
                    mainMessage: updatedMessage.mainMessage,
                    reply: updatedMessage.reply,
                    reaction: updatedMessage.reaction,
                    fileName: updatedMessage.fileName,
                    translations: updatedMessage.translations,
                    langSource: updatedMessage.langSource,
                    originalName: updatedMessage.originalName,
                    size: updatedMessage.size,
                    xmppId: updatedMessage.xmppId,
                    xmppFrom: updatedMessage.xmppFrom,
                    waveForm: updatedMessage.waveForm
                )
                messages[index] = editedMessage
                room.messages = messages
                
                MessageCache.shared.saveMessages(messages, forRoomJID: room.jid)
            }
        }
    }
}
