//
//  RoomsAPI+Rooms.swift
//  XMPPChatCore
//

import Foundation

extension RoomsAPI {
    /// Fetch user rooms via REST: GET /chats/my
    /// Automatically uses token from UserStore and refreshes if needed
    /// - Parameters:
    ///   - baseURL: API base URL, defaults to Ethora API
    ///   - appId: App ID used in `x-app-id` header (required by API)
    ///   - conferenceDomain: XMPP conference domain used to build room JIDs
    ///   - didRefresh: Internal flag to prevent refresh loops
    /// - Returns: Array of `Room` mapped from `ApiRoom`
    public static func getRooms(
        baseURL: URL = URL(string: "https://api.ethoradev.com/v1")!,
        appId: String? = nil,
        conferenceDomain: String = "conference.xmpp.ethoradev.com",
        didRefresh: Bool = false
    ) async throws -> [Room] {
        let url = baseURL.appendingPathComponent("chats/my")
        let response: RoomsResponse = try await performRequest(
            url: url,
            method: "GET",
            baseURL: baseURL,
            appId: appId,
            didRefresh: didRefresh,
            retryHandler: { refreshed in
                try await getRooms(baseURL: baseURL, appId: appId, conferenceDomain: conferenceDomain, didRefresh: refreshed)
            }
        )
        return response.items.map { Room(apiRoom: $0, conferenceDomain: conferenceDomain) }
    }
    
    // MARK: - Create Room
    
    /// Create a new room
    /// POST /chats
    public static func postRoom(
        title: String,
        type: RoomType,
        description: String? = nil,
        picture: String? = nil,
        members: [String]? = nil,
        baseURL: URL = URL(string: "https://api.ethoradev.com/v1")!,
        appId: String? = nil,
        didRefresh: Bool = false
    ) async throws -> ApiRoom {
        let url = baseURL.appendingPathComponent("chats")
        
        struct PostRoomBody: Codable {
            let title: String
            let type: String
            let description: String?
            let picture: String?
            let members: [String]?
        }
        
        let body = PostRoomBody(
            title: title,
            type: type.rawValue,
            description: description,
            picture: picture,
            members: members
        )
        
        struct PostRoomResponse: Codable {
            let result: ApiRoom
        }
        
        let response: PostRoomResponse = try await performRequest(
            url: url,
            method: "POST",
            body: body,
            baseURL: baseURL,
            appId: appId,
            didRefresh: didRefresh,
            retryHandler: { refreshed in
                try await postRoom(
                    title: title,
                    type: type,
                    description: description,
                    picture: picture,
                    members: members,
                    baseURL: baseURL,
                    appId: appId,
                    didRefresh: refreshed
                )
            }
        )
        return response.result
    }
    
    // MARK: - Create Private Room
    
    /// Create a private room
    /// POST /chats/private
    public static func postPrivateRoom(
        username: String,
        title: String = "Private chat",
        baseURL: URL = URL(string: "https://api.ethoradev.com/v1")!,
        appId: String? = nil,
        didRefresh: Bool = false
    ) async throws -> ApiRoom {
        let url = baseURL.appendingPathComponent("chats/private")
        
        struct PostPrivateRoomBody: Codable {
            let username: String
        }
        
        let body = PostPrivateRoomBody(username: username)
        
        struct PostPrivateRoomResponse: Codable {
            let result: ApiRoom
        }
        
        let response: PostPrivateRoomResponse = try await performRequest(
            url: url,
            method: "POST",
            body: body,
            baseURL: baseURL,
            appId: appId,
            didRefresh: didRefresh,
            retryHandler: { refreshed in
                try await postPrivateRoom(
                    username: username,
                    title: title,
                    baseURL: baseURL,
                    appId: appId,
                    didRefresh: refreshed
                )
            }
        )
        return response.result
    }
    
    // MARK: - Get Room By Name
    
    /// Get room by name
    /// GET /chats/my/{chatName}
    public static func getRoomByName(
        chatName: String,
        baseURL: URL = URL(string: "https://api.ethoradev.com/v1")!,
        appId: String? = nil,
        didRefresh: Bool = false
    ) async throws -> ApiRoom {
        let url = baseURL.appendingPathComponent("chats/my/\(chatName)")
        
        return try await performRequest(
            url: url,
            method: "GET",
            baseURL: baseURL,
            appId: appId,
            didRefresh: didRefresh,
            retryHandler: { refreshed in
                try await getRoomByName(chatName: chatName, baseURL: baseURL, appId: appId, didRefresh: refreshed)
            }
        )
    }
}
