//
//  CallsAPI.swift
//  XMPPChatCore
//
//  REST call creation. Mirrors createChatCall in
//  src/networking/api-requests/rooms.api.ts.
//

import Foundation

public enum CallsAPIError: Error, LocalizedError {
    case timeout

    public var errorDescription: String? {
        switch self {
        case .timeout:
            return "Call creation timed out"
        }
    }
}

public struct CallsAPI {
    /// Timeout for the create request (web CALL_CREATE_TIMEOUT_MS).
    public static let createTimeoutSeconds: TimeInterval = 15

    /// POST /chats/call/create/{chatName} with body `{ "kind": "audio" | "video" }`.
    /// `chatName` is the room JID localpart, not the display title.
    public static func createChatCall(
        chatName: String,
        kind: CallKind,
        baseURL: URL? = nil,
        appId: String? = nil,
        timeout: TimeInterval = createTimeoutSeconds
    ) async throws {
        let resolvedBaseURL = try await AppConfig.resolveBaseURL(baseURL)
        let url = resolvedBaseURL.appendingPathComponent("chats/call/create/\(chatName)")

        struct CreateCallBody: Codable {
            let kind: String
        }
        let body = CreateCallBody(kind: kind.rawValue)

        try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                let created: Bool = try await RoomsAPI.performRequest(
                    url: url,
                    method: "POST",
                    body: body,
                    baseURL: resolvedBaseURL,
                    appId: appId,
                    didRefresh: false
                )
                return created
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw CallsAPIError.timeout
            }
            defer { group.cancelAll() }
            _ = try await group.next()
        }
    }
}
