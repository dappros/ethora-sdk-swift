//
//  MessageNotification.swift
//  XMPPChatCore
//
//  Message notification model
//

import Foundation

public struct MessageNotification: Identifiable {
    public let id: String
    public let messageId: String
    public let roomJID: String
    public let roomName: String
    public let senderName: String
    public let messagePreview: String
    public let timestamp: Date
    
    public init(
        id: String = UUID().uuidString,
        messageId: String,
        roomJID: String,
        roomName: String,
        senderName: String,
        messagePreview: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.messageId = messageId
        self.roomJID = roomJID
        self.roomName = roomName
        self.senderName = senderName
        self.messagePreview = messagePreview
        self.timestamp = timestamp
    }
}
