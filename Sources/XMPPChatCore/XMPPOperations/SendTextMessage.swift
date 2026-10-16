//
//  SendTextMessage.swift
//  XMPPChatCore
//
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

        // `client.devServer` is non-empty by construction (failable
        // XMPPClient init enforces this); fall back is intentionally
        // gone so we never silently emit messages stamped with the SDK
        // author's WebSocket URL.
        guard let devServer = client?.devServer, !devServer.isEmpty else { return }
        
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

        // E2EE: in an e2ee room the body is encrypted and <data> rides beside it in the clear.
        // If encryption fails the message goes out in clear, as the web does.
        if E2EERuntime.isEnabled {
            let domain = E2EEManager.accountDomain(from: stream.jid)
            Task {
                do {
                    if let encrypted = try await self.e2eeEncryptedStanza(
                        roomJID: roomJID, id: id, content: [bodyStanza], cleartext: [dataStanza], domain: domain
                    ) {
                        stream.send(encrypted)
                        return
                    }
                } catch {
                    print("[E2EE] sending \(roomJID) in clear: \(error.localizedDescription)")
                }
                stream.send(messageStanza)
            }
            return
        }
        
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

        // E2EE: a sealed attachment (keys present) only ever goes out encrypted. The keys ride
        // in the encrypted <body>, and <data> carries clientEncrypted in the clear.
        if let keys = data.e2eeKeys, !keys.isEmpty {
            var sealedAttributes = dataAttributes
            sealedAttributes["clientEncrypted"] = "true"
            let sealedData = XMPPStanza(name: "data", attributes: sealedAttributes)
            let payload = "{\"v\":1,\"keys\":[" + keys.map(E2EEFileEnvelope.jsonString).joined(separator: ",") + "]}"
            let domain = E2EEManager.accountDomain(from: stream.jid)
            Task {
                do {
                    guard let encrypted = try await self.e2eeEncryptedStanza(
                        roomJID: roomJID,
                        id: id,
                        content: [XMPPStanza(name: "body", text: payload)],
                        cleartext: [sealedData, storeStanza],
                        domain: domain
                    ) else {
                        print("[E2EE] refusing to send sealed attachment to \(roomJID): room is not e2ee")
                        return
                    }
                    stream.send(encrypted)
                } catch {
                    print("[E2EE] refusing to send sealed attachment to \(roomJID): \(error.localizedDescription)")
                }
            }
            return
        }
        
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

        // E2EE: an edit in an e2ee room is encrypted like any other message. It is never sent in
        // clear, so a failed encryption drops the edit instead of leaking its text.
        if E2EERuntime.isEnabled {
            let domain = E2EEManager.accountDomain(from: stream.jid)
            Task {
                do {
                    if let encrypted = try await self.e2eeEncryptedStanza(
                        roomJID: chatId, id: id, content: [replaceStanza], cleartext: [], domain: domain
                    ) {
                        stream.send(encrypted)
                        return
                    }
                } catch {
                    print("[E2EE] dropping edit in \(chatId): \(error.localizedDescription)")
                    return
                }
                stream.send(messageStanza)
            }
            return
        }
        
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
    /// E2EE: attachment keys of a sealed upload (see E2EEFileEnvelope). Set only in e2ee rooms.
    public var e2eeKeys: [String]?
    
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


