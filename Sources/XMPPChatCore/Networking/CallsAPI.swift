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

/// Never-failing JSON tree, so a response of any shape can be read tolerantly.
struct CallJSONValue: Codable {
    let object: Any?

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            object = nil
        } else if let v = try? c.decode(Bool.self) {
            object = v
        } else if let v = try? c.decode(Double.self) {
            object = NSNumber(value: v)
        } else if let v = try? c.decode(String.self) {
            object = v
        } else if let v = try? c.decode([CallJSONValue].self) {
            object = v.map { $0.object as Any }
        } else if let v = try? c.decode([String: CallJSONValue].self) {
            object = v.mapValues { $0.object as Any }
        } else {
            object = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encodeNil()
    }
}

/// Client-reported state of a p2p call. There is no LiveKit webhook for these
/// calls, so the clients tell the server (fire and forget; LiveKit calls must
/// never send them, the server answers 409 CALL_NOT_P2P).
public enum CallStateReport: String, Sendable {
    case ringing
    case decline
    case connected
    case end
}

public struct IceServersResponse: Equatable, Sendable {
    public var enabled: Bool
    public var iceServers: [IceServerConfig]
    public var ttlSeconds: Double?
}

public struct CallsAPI {
    /// Runs a report in the background; the UI never waits on it.
    public static func fireAndForget(_ work: @escaping @Sendable () async -> Void) {
        Task.detached { await work() }
    }

    /// Timeout for the create request (web CALL_CREATE_TIMEOUT_MS).
    public static let createTimeoutSeconds: TimeInterval = 15

    /// POST /chats/call/create/{chatName} with body `{ "kind": "audio" | "video" }`.
    /// `chatName` is the room JID localpart, not the display title. The client
    /// never sends a transport: the server decides (`p2p` for private chats
    /// when enabled, `livekit` otherwise) and says so in the response.
    @discardableResult
    public static func createChatCall(
        chatName: String,
        kind: CallKind,
        baseURL: URL? = nil,
        appId: String? = nil,
        timeout: TimeInterval = createTimeoutSeconds
    ) async throws -> CallCreateResult {
        let resolvedBaseURL = try await AppConfig.resolveBaseURL(baseURL)
        let url = resolvedBaseURL.appendingPathComponent("chats/call/create/\(chatName)")

        struct CreateCallBody: Codable {
            let kind: String
        }
        let body = CreateCallBody(kind: kind.rawValue)

        return try await withThrowingTaskGroup(of: CallCreateResult.self) { group in
            group.addTask {
                let response: CallJSONValue = try await RoomsAPI.performRequest(
                    url: url,
                    method: "POST",
                    body: body,
                    baseURL: resolvedBaseURL,
                    appId: appId,
                    didRefresh: false
                )
                return try CallModeParsing.parseCallCreateResponse(response.object, fallbackKind: kind)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw CallsAPIError.timeout
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw CallsAPIError.timeout }
            return first
        }
    }

    /// POST /chats/call/state/{report}/{callId}. Never throws: a failure is
    /// only logged, the UI never waits on it.
    public static func reportCallState(
        _ report: CallStateReport,
        callId: String?,
        baseURL: URL? = nil,
        appId: String? = nil
    ) async {
        let id = (callId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        do {
            let resolvedBaseURL = try await AppConfig.resolveBaseURL(baseURL)
            let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
            let url = resolvedBaseURL.appendingPathComponent("chats/call/state/\(report.rawValue)/\(encoded)")
            let _: Bool = try await RoomsAPI.performRequest(
                url: url,
                method: "POST",
                body: nil,
                baseURL: resolvedBaseURL,
                appId: appId,
                didRefresh: false
            )
        } catch {
            NSLog("[call] state/%@ report failed: %@", report.rawValue, error.localizedDescription)
        }
    }

    /// GET /calls/ice-servers: fresh STUN/TURN credentials. Nil on any failure
    /// so callers can carry on with the servers they already have.
    public static func fetchIceServers(
        baseURL: URL? = nil,
        appId: String? = nil
    ) async -> IceServersResponse? {
        do {
            let resolvedBaseURL = try await AppConfig.resolveBaseURL(baseURL)
            let url = resolvedBaseURL.appendingPathComponent("calls/ice-servers")
            let response: CallJSONValue = try await RoomsAPI.performRequest(
                url: url,
                method: "GET",
                body: nil,
                baseURL: resolvedBaseURL,
                appId: appId,
                didRefresh: false
            )
            let data = (response.object as? [String: Any]) ?? [:]
            let servers = CallModeParsing.normalizeIceServers(object: data["iceServers"])
            let ttl = (data["ttlSeconds"] as? NSNumber)?.doubleValue
            return IceServersResponse(
                enabled: (data["enabled"] as? Bool) ?? !servers.isEmpty,
                iceServers: servers,
                ttlSeconds: (ttl ?? 0) > 0 ? ttl : nil
            )
        } catch {
            NSLog("[call] ice-servers fetch failed: %@", error.localizedDescription)
            return nil
        }
    }
}
