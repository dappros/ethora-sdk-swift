//
//  Room.swift
//  XMPPChatCore
//
//  Created from TypeScript models
//

import Foundation

public struct RoomMember: Codable, Identifiable, Equatable {
    public let firstName: String?
    public let lastName: String?
    public let xmppUsername: String?
    public let id: String
    public var banStatus: String?
    public var jid: String?
    public var name: String?
    public var role: String?
    public var lastActive: Int64?
    public var description: String?
    
    // Custom CodingKeys to map _id from API to id
    enum CodingKeys: String, CodingKey {
        case firstName
        case lastName
        case xmppUsername
        case id = "_id"  // Map _id from API to id
        case banStatus
        case jid
        case name
        case role
        case lastActive
        case description
    }
    
    // Custom decoder to handle _id -> id mapping
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.firstName = try container.decodeIfPresent(String.self, forKey: .firstName)
        self.lastName = try container.decodeIfPresent(String.self, forKey: .lastName)
        self.xmppUsername = try container.decodeIfPresent(String.self, forKey: .xmppUsername)
        self.id = try container.decode(String.self, forKey: .id)  // This will decode from "_id" key
        self.banStatus = try container.decodeIfPresent(String.self, forKey: .banStatus)
        self.jid = try container.decodeIfPresent(String.self, forKey: .jid)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.role = try container.decodeIfPresent(String.self, forKey: .role)
        self.lastActive = try container.decodeIfPresent(Int64.self, forKey: .lastActive)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
    }
    
    // Custom encoder to handle id -> _id mapping
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(firstName, forKey: .firstName)
        try container.encodeIfPresent(lastName, forKey: .lastName)
        try container.encodeIfPresent(xmppUsername, forKey: .xmppUsername)
        try container.encode(id, forKey: .id)  // This will encode to "_id" key
        try container.encodeIfPresent(banStatus, forKey: .banStatus)
        try container.encodeIfPresent(jid, forKey: .jid)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(role, forKey: .role)
        try container.encodeIfPresent(lastActive, forKey: .lastActive)
        try container.encodeIfPresent(description, forKey: .description)
    }
    
    public init(
        firstName: String? = nil,
        lastName: String? = nil,
        xmppUsername: String? = nil,
        id: String,
        banStatus: String? = nil,
        jid: String? = nil,
        name: String? = nil,
        role: String? = nil,
        lastActive: Int64? = nil,
        description: String? = nil
    ) {
        self.firstName = firstName
        self.lastName = lastName
        self.xmppUsername = xmppUsername
        self.id = id
        self.banStatus = banStatus
        self.jid = jid
        self.name = name
        self.role = role
        self.lastActive = lastActive
        self.description = description
    }
}

public struct Room: Codable, Identifiable, Equatable {
    public let id: String
    public let jid: String
    public let name: String
    public let title: String
    public var usersCnt: Int
    public var messages: [Message]
    public var isLoading: Bool
    public var roomBg: String?
    public var members: [RoomMember]?
    public var type: RoomType?
    public var createdAt: String?
    public var appId: String?
    public var createdBy: String?
    public var description: String?
    public var isAppChat: Bool?
    public var picture: String?
    public var updatedAt: String?
    public var lastMessage: LastMessage?
    public var lastMessageTimestamp: Int64?
    public var icon: String?
    public var composing: Bool?
    public var composingList: [String]?
    public var lastViewedTimestamp: Int64?
    public var unreadMessages: Int
    public var noMessages: Bool?
    public var role: String?
    public var messageStats: MessageStats?
    public var historyComplete: Bool?
    
    public init(
        id: String,
        jid: String,
        name: String,
        title: String,
        usersCnt: Int = 0,
        messages: [Message] = [],
        isLoading: Bool = false,
        roomBg: String? = nil,
        members: [RoomMember]? = nil,
        type: RoomType? = nil,
        createdAt: String? = nil,
        appId: String? = nil,
        createdBy: String? = nil,
        description: String? = nil,
        isAppChat: Bool? = nil,
        picture: String? = nil,
        updatedAt: String? = nil,
        lastMessage: LastMessage? = nil,
        lastMessageTimestamp: Int64? = nil,
        icon: String? = nil,
        composing: Bool? = nil,
        composingList: [String]? = nil,
        lastViewedTimestamp: Int64? = nil,
        unreadMessages: Int = 0,
        noMessages: Bool? = nil,
        role: String? = nil,
        messageStats: MessageStats? = nil,
        historyComplete: Bool? = nil
    ) {
        self.id = id
        self.jid = jid
        self.name = name
        self.title = title
        self.usersCnt = usersCnt
        self.messages = messages
        self.isLoading = isLoading
        self.roomBg = roomBg
        self.members = members
        self.type = type
        self.createdAt = createdAt
        self.appId = appId
        self.createdBy = createdBy
        self.description = description
        self.isAppChat = isAppChat
        self.picture = picture
        self.updatedAt = updatedAt
        self.lastMessage = lastMessage
        self.lastMessageTimestamp = lastMessageTimestamp
        self.icon = icon
        self.composing = composing
        self.composingList = composingList
        self.lastViewedTimestamp = lastViewedTimestamp
        self.unreadMessages = unreadMessages
        self.noMessages = noMessages
        self.role = role
        self.messageStats = messageStats
        self.historyComplete = historyComplete
    }
}

public enum RoomType: String, Codable {
    case `public` = "public"
    case group = "group"
    case `private` = "private"
}

// API-level room representation (matches TypeScript ApiRoom)
public struct ApiRoom: Codable {
    public let name: String
    public let type: RoomType
    public var title: String?
    public var description: String?
    public var picture: String?
    public var members: [RoomMember]?
    public var createdBy: String?
    public var appId: String?
    public var _id: String?
    public var isAppChat: Bool?
    public var createdAt: String?
    public var updatedAt: String?
    public var __v: Int?  // Changed from String? to Int? based on API response showing 0
    public var reported: Bool?
    
    // Explicit CodingKeys to ensure proper decoding
    enum CodingKeys: String, CodingKey {
        case name
        case type
        case title
        case description
        case picture
        case members
        case createdBy
        case appId
        case _id
        case isAppChat
        case createdAt
        case updatedAt
        case __v
        case reported
    }
}

public struct MessageStats: Codable, Equatable {
    public var lastMessageTimestamp: Int64?
    public var firstMessageTimestamp: Int64?
    
    public init(
        lastMessageTimestamp: Int64? = nil,
        firstMessageTimestamp: Int64? = nil
    ) {
        self.lastMessageTimestamp = lastMessageTimestamp
        self.firstMessageTimestamp = firstMessageTimestamp
    }
}

// Convenience initializer from ApiRoom (mirrors createRoomFromApi.ts)
public extension Room {
    init(apiRoom: ApiRoom, conferenceDomain: String, usersArrayLength: Int = 0) {
        let jid = "\(apiRoom.name)@\(conferenceDomain)"
        self.init(
            id: apiRoom._id ?? apiRoom.name,
            jid: jid,
            name: apiRoom.title ?? apiRoom.name,
            title: apiRoom.title ?? apiRoom.name,
            usersCnt: apiRoom.members?.count ?? (usersArrayLength + 1),
            messages: [],
            isLoading: false,
            roomBg: nil,
            members: apiRoom.members,
            type: apiRoom.type,
            createdAt: apiRoom.createdAt,
            appId: apiRoom.appId,
            createdBy: apiRoom.createdBy,
            description: apiRoom.description,
            isAppChat: apiRoom.isAppChat,
            picture: apiRoom.picture,
            updatedAt: apiRoom.updatedAt,
            lastMessage: nil,
            lastMessageTimestamp: nil,
            icon: (apiRoom.picture != nil && apiRoom.picture != "none") ? apiRoom.picture : nil,
            composing: nil,
            composingList: nil,
            lastViewedTimestamp: 0,
            unreadMessages: 0,
            noMessages: nil,
            role: nil,
            messageStats: nil,
            historyComplete: nil
        )
    }
}

