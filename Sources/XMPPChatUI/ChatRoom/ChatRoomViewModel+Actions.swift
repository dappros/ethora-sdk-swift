//
//  ChatRoomViewModel+Actions.swift
//  XMPPChatUI
//

import Foundation
import XMPPChatCore
#if os(iOS)
import UIKit
#endif

extension ChatRoomViewModel {
    public func sendMessage(_ text: String) {
        guard !text.isEmpty else { return }
        
        let user = UserStore.shared.currentUser
        let firstName = user?.firstName ?? "User"
        let lastName = user?.lastName ?? "Name"
        let walletAddress = user?.walletAddress ?? ""
        let photo = user?.profileImage ?? ""
        
        let messageId = "send-text-message-\(Int64(Date().timeIntervalSince1970 * 1000))"
        
        client.operations.sendTextMessage(
            roomJID: room.jid,
            firstName: firstName,
            lastName: lastName,
            photo: photo,
            walletAddress: walletAddress,
            userMessage: text,
            customId: messageId
        )
        
        let optimisticMessage = Message(
            id: messageId,
            user: User(
                id: currentUserId,
                name: "\(firstName) \(lastName)",
                firstName: firstName,
                lastName: lastName,
                profileImage: photo,
                xmppUsername: currentUserId
            ),
            date: Date(),
            body: text,
            roomJid: room.jid,
            pending: true,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            xmppId: messageId
        )
        
        handleIncomingMessage(optimisticMessage)
    }
    
    /// Send reply to a message
    public func sendReply(messageId: String, text: String, alsoSendToMain: Bool) {
        guard !text.isEmpty else { return }
        
        // Get current user info from UserStore
        let user = UserStore.shared.currentUser
        let firstName = user?.firstName ?? "User"
        let lastName = user?.lastName ?? "Name"
        let walletAddress = user?.walletAddress ?? ""
        let photo = user?.profileImage ?? ""
        
        // Send reply message with mainMessage set
        client.operations.sendTextMessage(
            roomJID: room.jid,
            firstName: firstName,
            lastName: lastName,
            photo: photo,
            walletAddress: walletAddress,
            userMessage: text,
            isReply: true,
            mainMessage: messageId
        )
        
        // If alsoSendToMain is true, send another message without mainMessage
        if alsoSendToMain {
            client.operations.sendTextMessage(
                roomJID: room.jid,
                firstName: firstName,
                lastName: lastName,
                photo: photo,
                walletAddress: walletAddress,
                userMessage: text,
                isReply: false,
                mainMessage: nil
            )
        }
        
        // Add optimistic reply message to UI
        let optimisticReply = Message(
            id: "pending-reply-\(Int64(Date().timeIntervalSince1970 * 1000))",
            user: User(
                id: currentUserId,
                name: "\(firstName) \(lastName)",
                firstName: firstName,
                lastName: lastName,
                profileImage: photo,
                xmppUsername: currentUserId
            ),
            date: Date(),
            body: text,
            roomJid: room.jid,
            pending: true,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            isReply: true,
            mainMessage: messageId
        )
        
        messages.append(optimisticReply)
        
        // Update room's messages array
        room.messages = messages
        
        // CRITICAL: Save pending message to cache immediately so it persists even if connection is lost
        MessageCache.shared.saveMessages(messages, forRoomJID: room.jid)
    }
    
    public func sendMedia(data: Data, type: String) {
        print("📤 ChatRoomViewModel.sendMedia: Called with type: \(type), size: \(data.count) bytes")
        
        guard let user = UserStore.shared.currentUser else {
            print("❌ ChatRoomViewModel.sendMedia: No current user")
            return
        }
        
        let messageId = "send-media-message-\(Int64(Date().timeIntervalSince1970 * 1000))"
        
        Task {
            do {
                var finalData = data
                var finalMimeType = type
                var finalFileName = "media_\(Int64(Date().timeIntervalSince1970 * 1000))"
                
                #if os(iOS)
                if type == "image/heic" || type == "image/heif" {
                    if let uiImage = UIImage(data: data) {
                        if let jpegData = uiImage.jpegData(compressionQuality: 0.8) {
                            finalData = jpegData
                            finalMimeType = "image/jpeg"
                            finalFileName = "\(finalFileName).jpg"
                        }
                    }
                } else {
                    let fileExtension: String
                    if type.starts(with: "image/") {
                        if type.contains("png") {
                            fileExtension = "png"
                        } else if type.contains("gif") {
                            fileExtension = "gif"
                        } else {
                            fileExtension = "jpg"
                        }
                    } else if type.starts(with: "video/") {
                        fileExtension = "mp4"
                    } else if type.contains("pdf") {
                        fileExtension = "pdf"
                    } else {
                        fileExtension = "bin"
                    }
                    finalFileName = "\(finalFileName).\(fileExtension)"
                }
                #else
                let fileExtension: String
                if type.starts(with: "image/") {
                    if type.contains("png") {
                        fileExtension = "png"
                    } else if type.contains("gif") {
                        fileExtension = "gif"
                    } else {
                        fileExtension = "jpg"
                    }
                } else if type.starts(with: "video/") {
                    fileExtension = "mp4"
                } else if type.contains("pdf") {
                    fileExtension = "pdf"
                } else {
                    fileExtension = "bin"
                }
                finalFileName = "\(finalFileName).\(fileExtension)"
                #endif
                
                guard let token = UserStore.shared.token else {
                    return
                }
                
                let uploadResponse = try await AuthAPI.uploadFile(
                    fileData: finalData,
                    fileName: finalFileName,
                    mimeType: finalMimeType,
                    token: token
                )
                
                guard let uploadResult = uploadResponse.results.first else {
                    return
                }
                
                guard let resultId = uploadResult._id,
                      let resultFilename = uploadResult.filename,
                      let resultMimetype = uploadResult.mimetype,
                      let resultSize = uploadResult.size,
                      let resultLocation = uploadResult.location,
                      let resultCreatedAt = uploadResult.createdAt else {
                    return
                }
                
                let expiresAtString: String?
                if let expiresAt = uploadResult.expiresAt {
                    expiresAtString = expiresAt == 0 ? nil : String(expiresAt)
                } else {
                    expiresAtString = nil
                }
                
                let mediaData = MediaMessageData(
                    firstName: user.firstName ?? "",
                    lastName: user.lastName ?? "",
                    walletAddress: user.walletAddress ?? "",
                    chatName: room.title,
                    createdAt: resultCreatedAt,
                    fileName: resultFilename,
                    userId: uploadResult.userId ?? user.id,
                    isVisible: uploadResult.isVisible ?? true,
                    userAvatar: user.profileImage,
                    expiresAt: expiresAtString,
                    location: resultLocation,
                    locationPreview: uploadResult.locationPreview,
                    mimetype: resultMimetype,
                    originalName: uploadResult.originalname ?? resultFilename,
                    ownerKey: uploadResult.ownerKey,
                    size: String(resultSize),
                    duration: uploadResult.duration,
                    updatedAt: uploadResult.updatedAt,
                    attachmentId: resultId,
                    roomJid: room.jid
                )
                
                client.operations.sendMediaMessage(
                    roomJID: room.jid,
                    data: mediaData,
                    id: messageId
                )
                
            } catch {
                print("❌ ChatRoomViewModel.sendMedia: Error - \(error.localizedDescription)")
            }
        }
    }
    
    public func editMessage(_ messageId: String, newText: String) {
        client.operations.editMessage(
            chatId: room.jid,
            messageId: messageId,
            text: newText
        )
        
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            let updatedMessage = messages[index]
            let newMessage = Message(
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
            messages[index] = newMessage
            room.messages = messages
            
            MessageCache.shared.saveMessages(messages, forRoomJID: room.jid)
            
            var updates = PartialMessageUpdate()
            updates.body = newText
            RoomStore.shared.updateMessage(
                roomJID: room.jid,
                messageId: messageId,
                updates: updates
            )
        }
    }
    
    public func resendMessage(_ message: Message) {
        if message.isMediafile == "true" || message.mimetype != nil {
            if let location = message.location,
               let url = URL(string: location) {
                Task {
                    do {
                        let data = try Data(contentsOf: url)
                        let mimeType = message.mimetype ?? "application/octet-stream"
                        sendMedia(data: data, type: mimeType)
                    } catch { }
                }
            }
        } else {
            sendMessage(message.body)
        }
    }
    
    public func deleteMessage(_ messageId: String) {
        client.operations.deleteMessage(room: room.jid, msgId: messageId)
        
        messages = messages.filter { $0.id != messageId }
        room.messages = messages
        
        MessageCache.shared.saveMessages(messages, forRoomJID: room.jid)
        RoomStore.shared.deleteMessage(roomJID: room.jid, messageId: messageId)
    }
    
    public func addReaction(messageId: String, emoji: String) {
        guard let user = UserStore.shared.currentUser else { return }
        
        let firstName = user.firstName ?? "User"
        let lastName = user.lastName ?? "Name"
        
        let currentMessage = messages.first { $0.id == messageId }
        let currentReactions = currentMessage?.reaction?[currentUserId]?.emoji ?? []
        
        var newReactions = currentReactions
        if let index = newReactions.firstIndex(of: emoji) {
            newReactions.remove(at: index)
        } else {
            newReactions.append(emoji)
        }
        
        let reactionData = ReactionData(firstName: firstName, lastName: lastName)
        
        client.operations.sendMessageReaction(
            messageId: messageId,
            roomJid: room.jid,
            reactionsList: newReactions,
            data: reactionData
        )
        
        let fromJid: String = ""
        let dataDict: [String: String] = [
            "senderFirstName": firstName,
            "senderLastName": lastName
        ]
        
        RoomStore.shared.setReactions(
            roomJID: room.jid,
            messageId: messageId,
            reactions: newReactions,
            from: fromJid,
            data: dataDict
        )
        
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            var updatedMessage = messages[index]
            if updatedMessage.reaction == nil {
                updatedMessage.reaction = [:]
            }
            let fromId = fromJid.components(separatedBy: "@").first ?? fromJid
            if newReactions.isEmpty {
                updatedMessage.reaction?.removeValue(forKey: fromId)
            } else {
                updatedMessage.reaction?[fromId] = ReactionMessage(emoji: newReactions, data: dataDict)
            }
            messages[index] = updatedMessage
            room.messages = messages
            
            MessageCache.shared.saveMessages(messages, forRoomJID: room.jid)
        }
    }
    
    public func cancelEdit() {
        isEditing = false
        editText = nil
        editMessageId = nil
    }
    
    public func startTyping() {
        guard let user = UserStore.shared.currentUser else { return }
        let fullName = "\(user.firstName ?? "") \(user.lastName ?? "")".trimmingCharacters(in: .whitespaces)
        
        if !fullName.isEmpty {
            client.operations.sendTypingRequest(
                chatId: room.jid,
                fullName: fullName,
                start: true
            )
        }
    }
    
    public func stopTyping() {
        guard let user = UserStore.shared.currentUser else { return }
        let fullName = "\(user.firstName ?? "") \(user.lastName ?? "")".trimmingCharacters(in: .whitespaces)
        
        if !fullName.isEmpty {
            client.operations.sendTypingRequest(
                chatId: room.jid,
                fullName: fullName,
                start: false
            )
        }
    }
}
