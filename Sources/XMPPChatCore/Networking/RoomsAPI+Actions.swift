//
//  RoomsAPI+Actions.swift
//  XMPPChatCore
//

import Foundation

extension RoomsAPI {
    // MARK: - Report Room

    /// Report a room
    /// POST /chats/reports/{chatName}
    public static func postReportRoom(
        chatName: String,
        category: String,
        text: String? = nil,
        baseURL: URL? = nil,
        appId: String? = nil,
        didRefresh: Bool = false
    ) async throws -> Bool {
        let resolvedBaseURL = try await AppConfig.resolveBaseURL(baseURL)
        let url = resolvedBaseURL.appendingPathComponent("chats/reports/\(chatName)")

        struct ReportRoomBody: Codable {
            let category: String
            let text: String?
        }

        let body = ReportRoomBody(category: category, text: text)

        return try await performRequest(
            url: url,
            method: "POST",
            body: body,
            baseURL: resolvedBaseURL,
            appId: appId,
            didRefresh: didRefresh
        )
    }

    // MARK: - Report Message

    /// Report a message
    /// POST /chats/reports/{chatName}/messages/{messageId}
    public static func postReportMessage(
        chatName: String,
        messageId: String,
        category: String,
        text: String? = nil,
        baseURL: URL? = nil,
        appId: String? = nil,
        didRefresh: Bool = false
    ) async throws -> Bool {
        let resolvedBaseURL = try await AppConfig.resolveBaseURL(baseURL)
        let url = resolvedBaseURL.appendingPathComponent("chats/reports/\(chatName)/messages/\(messageId)")

        struct ReportMessageBody: Codable {
            let category: String
            let text: String?
        }

        let body = ReportMessageBody(category: category, text: text)

        return try await performRequest(
            url: url,
            method: "POST",
            body: body,
            baseURL: resolvedBaseURL,
            appId: appId,
            didRefresh: didRefresh
        )
    }

    // MARK: - Add Room Members

    /// Add members to a room
    /// POST /chats/users-access
    public static func postAddRoomMember(
        chatName: String,
        members: [String],
        baseURL: URL? = nil,
        appId: String? = nil,
        didRefresh: Bool = false
    ) async throws -> [RoomMember] {
        let resolvedBaseURL = try await AppConfig.resolveBaseURL(baseURL)
        let url = resolvedBaseURL.appendingPathComponent("chats/users-access")

        struct AddRoomMemberBody: Codable {
            let chatName: String
            let members: [String]
        }

        let body = AddRoomMemberBody(chatName: chatName, members: members)

        struct AddRoomMemberResponse: Codable {
            let results: [RoomMember]
        }

        let response: AddRoomMemberResponse = try await performRequest(
            url: url,
            method: "POST",
            body: body,
            baseURL: resolvedBaseURL,
            appId: appId,
            didRefresh: didRefresh
        )
        return response.results
    }

    // MARK: - Delete Room Members

    /// Remove members from a room
    /// DELETE /chats/users-access
    public static func deleteRoomMember(
        chatName: String,
        members: [String],
        baseURL: URL? = nil,
        appId: String? = nil,
        didRefresh: Bool = false
    ) async throws -> Bool {
        let resolvedBaseURL = try await AppConfig.resolveBaseURL(baseURL)
        let url = resolvedBaseURL.appendingPathComponent("chats/users-access")

        struct DeleteRoomMemberBody: Codable {
            let chatName: String
            let members: [String]
        }

        let body = DeleteRoomMemberBody(chatName: chatName, members: members)

        return try await performRequest(
            url: url,
            method: "DELETE",
            body: body,
            baseURL: resolvedBaseURL,
            appId: appId,
            didRefresh: didRefresh
        )
    }

    // MARK: - Delete Room

    /// Delete a room
    /// DELETE /chats
    public static func deleteRoom(
        name: String,
        baseURL: URL? = nil,
        appId: String? = nil,
        didRefresh: Bool = false
    ) async throws -> Bool {
        let resolvedBaseURL = try await AppConfig.resolveBaseURL(baseURL)
        let url = resolvedBaseURL.appendingPathComponent("chats")

        struct DeleteRoomBody: Codable {
            let name: String
        }

        let body = DeleteRoomBody(name: name)

        return try await performRequest(
            url: url,
            method: "DELETE",
            body: body,
            baseURL: resolvedBaseURL,
            appId: appId,
            didRefresh: didRefresh
        )
    }
}

// MARK: - Per-chat mute

extension RoomsAPI {
    /// Mute notifications for one chat (the caller's own preference).
    /// PUT /chats/my/{chatName}/mute, body `{}`. Returns true on success.
    public static func muteRoom(
        chatName: String,
        baseURL: URL? = nil,
        appId: String? = nil,
        didRefresh: Bool = false
    ) async throws -> Bool {
        let resolvedBaseURL = try await AppConfig.resolveBaseURL(baseURL)
        let url = resolvedBaseURL.appendingPathComponent("chats/my/\(chatName)/mute")

        struct EmptyBody: Codable {}

        return try await performRequest(
            url: url,
            method: "PUT",
            body: EmptyBody(),
            baseURL: resolvedBaseURL,
            appId: appId,
            didRefresh: didRefresh
        )
    }

    /// Unmute one chat. DELETE /chats/my/{chatName}/mute. Returns true on success.
    public static func unmuteRoom(
        chatName: String,
        baseURL: URL? = nil,
        appId: String? = nil,
        didRefresh: Bool = false
    ) async throws -> Bool {
        let resolvedBaseURL = try await AppConfig.resolveBaseURL(baseURL)
        let url = resolvedBaseURL.appendingPathComponent("chats/my/\(chatName)/mute")

        return try await performRequest(
            url: url,
            method: "DELETE",
            body: nil,
            baseURL: resolvedBaseURL,
            appId: appId,
            didRefresh: didRefresh
        )
    }
}

// MARK: - Report room category list

extension RoomsAPI {
    /// Categories offered by the web report form. The `id` is the value sent
    /// as `category` (an API contract), so it stays English whatever the UI language.
    public static let reportCategories: [String] = [
        "Spam",
        "Violence",
        "Child Abuse",
        "Pornography",
        "Personal Details",
        "Illegal Drugs",
        "Other",
    ]
}
