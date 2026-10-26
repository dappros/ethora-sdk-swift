//
//  RoomsAPI+Public.swift
//  XMPPChatCore
//
//  Public chats directory. Mirrors src/networking/api-requests/publicChats.api.ts
//

import Foundation

/// One entry of GET /chats/public: a chat anyone in the app may join.
public struct PublicChat: Equatable {
    /// Room name: the local part of its JID.
    public let name: String
    public let title: String
    public let description: String
    public let picture: String
    public let e2ee: Bool
}

/// One page of the public chats directory.
public struct PublicChatsPage: Equatable {
    public let items: [PublicChat]
    public let total: Int
    public let offset: Int
    public let limit: Int
    /// Server rows consumed so far, including hidden (reported) ones.
    /// Pass this as the next `offset`.
    public let nextOffset: Int
}

extension RoomsAPI {
    /// The endpoint rejects anything above 50 with a validation error.
    public static let publicChatsPageSize = 50

    /// Raw row as the backend sends it. Every field is optional on the wire.
    struct RawPublicChat: Codable {
        let name: String?
        let title: String?
        let description: String?
        let picture: String?
        let type: String?
        let e2ee: Bool?
        let reported: Bool?
    }

    struct PublicChatsResponse: Codable {
        let items: [RawPublicChat]?
        let total: Int?
        let offset: Int?
        let limit: Int?
    }

    /// Maps raw rows to directory entries: rows without a name and reported chats are dropped.
    static func mapPublicChats(_ raw: [RawPublicChat]) -> [PublicChat] {
        raw.compactMap { chat -> PublicChat? in
            guard let name = chat.name, !name.isEmpty, chat.reported != true else { return nil }
            return PublicChat(
                name: name,
                title: (chat.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                description: (chat.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                picture: chat.picture ?? "",
                e2ee: chat.e2ee ?? false
            )
        }
    }

    /// One page of public chats. GET /chats/public?limit={<=50}&offset={n}
    public static func getPublicChats(
        offset: Int = 0,
        limit: Int = publicChatsPageSize,
        baseURL: URL? = nil,
        appId: String? = nil,
        didRefresh: Bool = false
    ) async throws -> PublicChatsPage {
        let resolvedBaseURL = try await AppConfig.resolveBaseURL(baseURL)
        let pageSize = min(max(limit, 1), publicChatsPageSize)
        let safeOffset = max(offset, 0)

        var components = URLComponents(
            url: resolvedBaseURL.appendingPathComponent("chats/public"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "limit", value: String(pageSize)),
            URLQueryItem(name: "offset", value: String(safeOffset)),
        ]
        guard let url = components?.url else {
            throw RoomsAPIError.networkError("Invalid public chats URL")
        }

        let response: PublicChatsResponse = try await performRequest(
            url: url,
            method: "GET",
            baseURL: resolvedBaseURL,
            appId: appId,
            didRefresh: didRefresh
        )
        let raw = response.items ?? []
        return PublicChatsPage(
            items: mapPublicChats(raw),
            total: response.total ?? 0,
            offset: response.offset ?? safeOffset,
            limit: response.limit ?? pageSize,
            nextOffset: safeOffset + raw.count
        )
    }
}
