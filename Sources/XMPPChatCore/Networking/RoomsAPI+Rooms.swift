//
//  RoomsAPI+Rooms.swift
//  XMPPChatCore
//

import Foundation

extension RoomsAPI {
    /// Fetch user rooms via REST: GET /chats/my
    /// Automatically uses token from UserStore and refreshes if needed.
    /// All endpoint values default to the host's `ChatConfig` —
    /// `baseURL` falls back to `ChatConfig.baseUrl` and `conferenceDomain`
    /// to `ChatConfig.xmppSettings.conference`. Throws `ConfigError`
    /// if neither side provides them.
    public static func getRooms(
        baseURL: URL? = nil,
        appId: String? = nil,
        conferenceDomain: String? = nil,
        didRefresh: Bool = false
    ) async throws -> [Room] {
        let resolvedBaseURL = try await AppConfig.resolveBaseURL(baseURL)
        let resolvedConference = try await AppConfig.resolveConferenceDomain(conferenceDomain)
        let url = resolvedBaseURL.appendingPathComponent("chats/my")
        let response: RoomsResponse = try await performRequest(
            url: url,
            method: "GET",
            baseURL: resolvedBaseURL,
            appId: appId,
            didRefresh: didRefresh
        )
        return response.items.compactMap { Room(apiRoom: $0, conferenceDomain: resolvedConference) }
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
        baseURL: URL? = nil,
        appId: String? = nil,
        didRefresh: Bool = false
    ) async throws -> ApiRoom {
        let resolvedBaseURL = try await AppConfig.resolveBaseURL(baseURL)
        let url = resolvedBaseURL.appendingPathComponent("chats")

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
            baseURL: resolvedBaseURL,
            appId: appId,
            didRefresh: didRefresh
        )
        return response.result
    }

    // MARK: - Create Private Room

    /// Create a private room
    /// POST /chats/private
    public static func postPrivateRoom(
        username: String,
        title: String = "Private chat",
        baseURL: URL? = nil,
        appId: String? = nil,
        didRefresh: Bool = false
    ) async throws -> ApiRoom {
        let resolvedBaseURL = try await AppConfig.resolveBaseURL(baseURL)
        let url = resolvedBaseURL.appendingPathComponent("chats/private")

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
            baseURL: resolvedBaseURL,
            appId: appId,
            didRefresh: didRefresh
        )
        return response.result
    }

    // MARK: - Get Room By Name

    /// Get room by name
    /// GET /chats/my/{chatName}
    public static func getRoomByName(
        chatName: String,
        baseURL: URL? = nil,
        appId: String? = nil,
        didRefresh: Bool = false
    ) async throws -> ApiRoom {
        let resolvedBaseURL = try await AppConfig.resolveBaseURL(baseURL)
        let url = resolvedBaseURL.appendingPathComponent("chats/my/\(chatName)")
        print("🔍 getRoomByName/MY/! \(url)")

        return try await performRequest(
            url: url,
            method: "GET",
            baseURL: resolvedBaseURL,
            appId: appId,
            didRefresh: didRefresh
        )
    }
}
