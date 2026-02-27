//
//  ChatEvents.swift
//  XMPPChatCore
//

import Foundation

public struct ChatEventHandlers {
    public let onMessageSent: ((MessageSentEvent) -> Void)?
    public let onMessageFailed: ((MessageFailedEvent) -> Void)?
    public let onMessageEdited: ((MessageEditedEvent) -> Void)?
    
    public init(
        onMessageSent: ((MessageSentEvent) -> Void)? = nil,
        onMessageFailed: ((MessageFailedEvent) -> Void)? = nil,
        onMessageEdited: ((MessageEditedEvent) -> Void)? = nil
    ) {
        self.onMessageSent = onMessageSent
        self.onMessageFailed = onMessageFailed
        self.onMessageEdited = onMessageEdited
    }
}

public struct MessageSentEvent {
    public let message: String
    public let roomJID: String
    public let user: User
    public let messageType: MessageType
    public let metadata: [String: Any]?
    
    public init(message: String, roomJID: String, user: User, messageType: MessageType, metadata: [String: Any]? = nil) {
        self.message = message
        self.roomJID = roomJID
        self.user = user
        self.messageType = messageType
        self.metadata = metadata
    }
}

public struct MessageFailedEvent {
    public let message: String
    public let roomJID: String
    public let error: Error
    public let messageType: MessageType
    
    public init(message: String, roomJID: String, error: Error, messageType: MessageType) {
        self.message = message
        self.roomJID = roomJID
        self.error = error
        self.messageType = messageType
    }
}

public struct MessageEditedEvent {
    public let messageId: String
    public let newMessage: String
    public let roomJID: String
    public let user: User
    
    public init(messageId: String, newMessage: String, roomJID: String, user: User) {
        self.messageId = messageId
        self.newMessage = newMessage
        self.roomJID = roomJID
        self.user = user
    }
}

public enum MessageType: String, Codable {
    case text = "text"
    case media = "media"
}
