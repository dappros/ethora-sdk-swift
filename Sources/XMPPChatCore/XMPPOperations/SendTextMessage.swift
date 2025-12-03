//
//  SendTextMessage.swift
//  XMPPChatCore
//
//  Translated from sendTextMessage.xmpp.ts
//

import Foundation

public class XMPPOperations {
    internal weak var client: XMPPClient?
    
    internal init(client: XMPPClient) {
        self.client = client
    }
    
    public func sendTextMessage(
        roomJID: String,
        firstName: String,
        lastName: String,
        photo: String,
        walletAddress: String,
        userMessage: String,
        notDisplayedValue: String? = nil,
        isReply: Bool = false,
        showInChannel: Bool = false,
        mainMessage: String? = nil,
        customId: String? = nil
    ) {
        let id = customId ?? (isReply ? "send-reply-message-\(Int64(Date().timeIntervalSince1970 * 1000))" : "send-text-message-\(Int64(Date().timeIntervalSince1970 * 1000))")
        
        guard let stream = client?.xmppStream else { return }
        
        let devServer = client?.devServer ?? "wss://xmpp.ethoradev.com:5443/ws"
        
        let dataStanza = XMPPStanza(
            name: "data",
            attributes: [
                "xmlns": devServer,
                "senderFirstName": firstName,
                "senderLastName": lastName,
                "fullName": "\(firstName) \(lastName)",
                "photoURL": photo,
                "senderJID": stream.jid ?? "",
                "senderWalletAddress": walletAddress,
                "roomJid": roomJID,
                "isSystemMessage": "false",
                "tokenAmount": "0",
                "quickReplies": "",
                "notDisplayedValue": notDisplayedValue ?? "",
                "showInChannel": showInChannel ? "true" : "false",
                "isReply": isReply ? "true" : "false",
                "mainMessage": mainMessage ?? ""
            ]
        )
        
        let bodyStanza = XMPPStanza(name: "body", text: userMessage)
        
        let messageStanza = XMPPStanza(
            name: "message",
            attributes: [
                "to": roomJID,
                "type": "groupchat",
                "id": id
            ],
            children: [dataStanza, bodyStanza]
        )
        
        stream.send(messageStanza)
    }
    
    public func sendMediaMessage(
        roomJID: String,
        data: MediaMessageData,
        id: String
    ) {
        guard let stream = client?.xmppStream else { return }
        
        let dataAttributes: [String: String] = [
            "senderJID": stream.jid ?? "",
            "senderFirstName": data.firstName,
            "senderLastName": data.lastName,
            "senderWalletAddress": data.walletAddress,
            "isSystemMessage": "false",
            "tokenAmount": "0",
            "receiverMessageId": "0",
            "mucname": data.chatName,
            "photoURL": data.userAvatar ?? "",
            "isMediafile": "true",
            "createdAt": data.createdAt,
            "expiresAt": data.expiresAt ?? "",
            "fileName": data.fileName,
            "isVisible": data.isVisible ? "true" : "false",
            "location": data.location ?? "",
            "locationPreview": data.locationPreview ?? "",
            "mimetype": data.mimetype ?? "",
            "originalName": data.originalName ?? "",
            "ownerKey": data.ownerKey ?? "",
            "size": data.size ?? "",
            "duration": data.duration ?? "",
            "updatedAt": data.updatedAt ?? "",
            "userId": data.userId,
            "waveForm": data.waveForm ?? "",
            "attachmentId": data.attachmentId ?? "",
            "isReply": (data.isReply ?? false) ? "true" : "false",
            "showInChannel": (data.showInChannel ?? false) ? "true" : "false",
            "mainMessage": data.mainMessage ?? "",
            "roomJid": data.roomJid ?? ""
        ]
        
        let bodyStanza = XMPPStanza(name: "body", text: "media")
        let storeStanza = XMPPStanza(name: "store", attributes: ["xmlns": "urn:xmpp:hints"])
        let dataStanza = XMPPStanza(name: "data", attributes: dataAttributes)
        
        let messageStanza = XMPPStanza(
            name: "message",
            attributes: [
                "id": id,
                "type": "groupchat",
                "from": stream.jid ?? "",
                "to": roomJID
            ],
            children: [bodyStanza, storeStanza, dataStanza]
        )
        
        stream.send(messageStanza)
    }
    
    public func deleteMessage(room: String, msgId: String) {
        guard let stream = client?.xmppStream else { return }
        
        let bodyStanza = XMPPStanza(name: "body", text: "wow")
        let deleteStanza = XMPPStanza(name: "delete", attributes: ["id": msgId])
        
        let messageStanza = XMPPStanza(
            name: "message",
            attributes: [
                "from": stream.jid ?? "",
                "to": room,
                "id": "deleteMessageStanza",
                "type": "groupchat"
            ],
            children: [bodyStanza, deleteStanza]
        )
        
        stream.send(messageStanza)
    }
    
    public func editMessage(chatId: String, messageId: String, text: String) {
        guard let stream = client?.xmppStream else { return }
        
        let id = "edit-message-\(Int64(Date().timeIntervalSince1970 * 1000))"
        let replaceStanza = XMPPStanza(
            name: "replace",
            attributes: [
                "id": messageId,
                "text": text
            ]
        )
        
        let messageStanza = XMPPStanza(
            name: "message",
            attributes: [
                "to": chatId,
                "type": "groupchat",
                "id": id
            ],
            children: [replaceStanza]
        )
        
        stream.send(messageStanza)
    }
    
    public func sendMessageReaction(
        messageId: String,
        roomJid: String,
        reactionsList: [String],
        data: ReactionData,
        reactionSymbol: String? = nil
    ) {
        guard let stream = client?.xmppStream else { return }
        
        let id = "message-reaction:\(Int64(Date().timeIntervalSince1970 * 1000))"
        
        let reactionChildren = reactionsList.map { emoji in
            XMPPStanza(name: "reaction", text: emoji)
        }
        
        let reactionsStanza = XMPPStanza(
            name: "reactions",
            attributes: [
                "id": messageId,
                "from": stream.jid ?? "",
                "xmlns": "urn:xmpp:reactions:0"
            ],
            children: reactionChildren
        )
        
        let dataStanza = XMPPStanza(
            name: "data",
            attributes: [
                "senderFirstName": data.firstName,
                "senderLastName": data.lastName
            ]
        )
        
        let storeStanza = XMPPStanza(name: "store", attributes: ["xmlns": "urn:xmpp:hints"])
        
        let messageStanza = XMPPStanza(
            name: "message",
            attributes: [
                "id": id,
                "type": "groupchat",
                "from": stream.jid ?? "",
                "to": roomJid
            ],
            children: [reactionsStanza, dataStanza, storeStanza]
        )
        
        stream.send(messageStanza)
    }
    
    public func sendTypingRequest(chatId: String, fullName: String, start: Bool) {
        guard let stream = client?.xmppStream else { return }
        
        let id = start ? "typing-\(Int64(Date().timeIntervalSince1970 * 1000))" : "stop-typing-\(Int64(Date().timeIntervalSince1970 * 1000))"
        
        let composingStanza = XMPPStanza(
            name: start ? "composing" : "paused",
            attributes: ["xmlns": "http://jabber.org/protocol/chatstates"]
        )
        
        let dataStanza = XMPPStanza(
            name: "data",
            attributes: ["fullName": fullName]
        )
        
        let messageStanza = XMPPStanza(
            name: "message",
            attributes: [
                "type": "groupchat",
                "id": id,
                "to": chatId
            ],
            children: [composingStanza, dataStanza]
        )
        
        stream.send(messageStanza)
    }
}

// MARK: - Supporting Types
public struct MediaMessageData {
    public let firstName: String
    public let lastName: String
    public let walletAddress: String
    public let chatName: String
    public let createdAt: String
    public let fileName: String
    public let userId: String
    public let isVisible: Bool
    public var userAvatar: String?
    public var expiresAt: String?
    public var location: String?
    public var locationPreview: String?
    public var mimetype: String?
    public var originalName: String?
    public var ownerKey: String?
    public var size: String?
    public var duration: String?
    public var updatedAt: String?
    public var waveForm: String?
    public var attachmentId: String?
    public var isReply: Bool?
    public var showInChannel: Bool?
    public var mainMessage: String?
    public var roomJid: String?
    
    public init(
        firstName: String,
        lastName: String,
        walletAddress: String,
        chatName: String,
        createdAt: String,
        fileName: String,
        userId: String,
        isVisible: Bool,
        userAvatar: String? = nil,
        expiresAt: String? = nil,
        location: String? = nil,
        locationPreview: String? = nil,
        mimetype: String? = nil,
        originalName: String? = nil,
        ownerKey: String? = nil,
        size: String? = nil,
        duration: String? = nil,
        updatedAt: String? = nil,
        waveForm: String? = nil,
        attachmentId: String? = nil,
        isReply: Bool? = nil,
        showInChannel: Bool? = nil,
        mainMessage: String? = nil,
        roomJid: String? = nil
    ) {
        self.firstName = firstName
        self.lastName = lastName
        self.walletAddress = walletAddress
        self.chatName = chatName
        self.createdAt = createdAt
        self.fileName = fileName
        self.userId = userId
        self.isVisible = isVisible
        self.userAvatar = userAvatar
        self.expiresAt = expiresAt
        self.location = location
        self.locationPreview = locationPreview
        self.mimetype = mimetype
        self.originalName = originalName
        self.ownerKey = ownerKey
        self.size = size
        self.duration = duration
        self.updatedAt = updatedAt
        self.waveForm = waveForm
        self.attachmentId = attachmentId
        self.isReply = isReply
        self.showInChannel = showInChannel
        self.mainMessage = mainMessage
        self.roomJid = roomJid
    }
}

public struct ReactionData {
    public let firstName: String
    public let lastName: String
    
    public init(firstName: String, lastName: String) {
        self.firstName = firstName
        self.lastName = lastName
    }
}


