//
//  Message.swift
//  XMPPChatCore
//
//  Created from TypeScript models
//

import Foundation

public struct Message: Codable, Identifiable, Equatable {
    public let id: String
    public let user: User
    public let date: Date
    public let body: String
    public let roomJid: String
    public var key: String?
    public var coinsInMessage: String?
    public var numberOfReplies: Int?
    public var isSystemMessage: String?
    public var isMediafile: String?
    public var locationPreview: String?
    public var mimetype: String?
    public var location: String?
    public var pending: Bool?
    public var timestamp: Int64?
    public var showInChannel: String?
    public var activeMessage: Bool?
    public var isReply: Bool?
    public var isDeleted: Bool?
    public var mainMessage: String?
    public var reply: [Reply]?
    public var reaction: [String: ReactionMessage]?
    public var fileName: String?
    public var translations: [String: String]?
    public var langSource: String?
    public var originalName: String?
    public var size: String?
    public var xmppId: String?
    public var xmppFrom: String?
    
    public init(
        id: String,
        user: User,
        date: Date,
        body: String,
        roomJid: String,
        key: String? = nil,
        coinsInMessage: String? = nil,
        numberOfReplies: Int? = nil,
        isSystemMessage: String? = nil,
        isMediafile: String? = nil,
        locationPreview: String? = nil,
        mimetype: String? = nil,
        location: String? = nil,
        pending: Bool? = nil,
        timestamp: Int64? = nil,
        showInChannel: String? = nil,
        activeMessage: Bool? = nil,
        isReply: Bool? = nil,
        isDeleted: Bool? = nil,
        mainMessage: String? = nil,
        reply: [Reply]? = nil,
        reaction: [String: ReactionMessage]? = nil,
        fileName: String? = nil,
        translations: [String: String]? = nil,
        langSource: String? = nil,
        originalName: String? = nil,
        size: String? = nil,
        xmppId: String? = nil,
        xmppFrom: String? = nil
    ) {
        self.id = id
        self.user = user
        self.date = date
        self.body = body
        self.roomJid = roomJid
        self.key = key
        self.coinsInMessage = coinsInMessage
        self.numberOfReplies = numberOfReplies
        self.isSystemMessage = isSystemMessage
        self.isMediafile = isMediafile
        self.locationPreview = locationPreview
        self.mimetype = mimetype
        self.location = location
        self.pending = pending
        self.timestamp = timestamp
        self.showInChannel = showInChannel
        self.activeMessage = activeMessage
        self.isReply = isReply
        self.isDeleted = isDeleted
        self.mainMessage = mainMessage
        self.reply = reply
        self.reaction = reaction
        self.fileName = fileName
        self.translations = translations
        self.langSource = langSource
        self.originalName = originalName
        self.size = size
        self.xmppId = xmppId
        self.xmppFrom = xmppFrom
    }
}

public typealias Reply = Message

public struct ReactionMessage: Codable, Equatable {
    public let emoji: [String]
    public let data: [String: String]
    
    public init(emoji: [String], data: [String: String]) {
        self.emoji = emoji
        self.data = data
    }
}

public struct LastMessage: Codable, Equatable {
    public let body: String
    public var date: Date?
    public var emoji: String?
    public var locationPreview: String?
    public var filename: String?
    public var mimetype: String?
    public var originalName: String?
    
    public init(
        body: String,
        date: Date? = nil,
        emoji: String? = nil,
        locationPreview: String? = nil,
        filename: String? = nil,
        mimetype: String? = nil,
        originalName: String? = nil
    ) {
        self.body = body
        self.date = date
        self.emoji = emoji
        self.locationPreview = locationPreview
        self.filename = filename
        self.mimetype = mimetype
        self.originalName = originalName
    }
}

