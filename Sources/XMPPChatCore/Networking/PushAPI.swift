//
//  PushAPI.swift
//  XMPPChatCore
//
//  Push subscription REST calls. Translated from RN
//  src/networking/api-requests/push.api.ts, wire-compatible with the web SDK:
//    POST   /v1/push/subscription/{appId}   { registrationToken, deviceType, tokenType }
//    DELETE /v1/push/subscription/{appId}   { registrationToken }   (404 -> DELETE /v1/users/endpoints)
//    POST   {pushNotifications.apiUrl}/subscriptions   gateway mode, Bearer token
//

import Foundation

public enum PushDeviceType: String, Codable {
    case ios
    case android
    case web
}

/// Kind of push token. The backend keys its delivery on it.
public enum PushTokenType: String, Codable, Equatable {
    case apns
    case apnsVoip = "apns-voip"
    case fcm
    case expo

    /// `ExponentPushToken[...]` is expo, 64 or more hex characters is apns,
    /// anything else is fcm. Same rule as RN `detectPushTokenType`.
    public static func detect(_ token: String) -> PushTokenType {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("ExponentPushToken[") || trimmed.hasPrefix("ExpoPushToken["))
            && trimmed.hasSuffix("]") {
            return .expo
        }
        if trimmed.count >= 64, trimmed.allSatisfy({ $0.isHexDigit }) {
            return .apns
        }
        return .fcm
    }
}

/// A token the host hands over through `pushNotifications.getPushTokens`.
public struct PushTokenRegistration: Codable, Equatable {
    public let token: String
    public let tokenType: PushTokenType

    public init(token: String, tokenType: PushTokenType) {
        self.token = token
        self.tokenType = tokenType
    }
}

public struct PushAPI {
    // MARK: - Request bodies

    struct SubscriptionBody: Encodable {
        let registrationToken: String
        let deviceType: String
        let tokenType: String?
    }

    struct LegacySubscriptionBody: Encodable {
        let registrationToken: String
        let deviceType: String
    }

    struct ReleaseBody: Encodable {
        let registrationToken: String
    }

    struct EndpointBody: Encodable {
        let endpoint: String
    }

    struct GatewayBody: Encodable {
        let projectName: String
        let registrationToken: String
        let deviceType: String
        let jid: String
    }

    // MARK: - Direct registration

    /// Register a push token with the Ethora backend.
    ///
    /// If the backend answers 422 "not allowed" to an `apns` or `fcm` token type,
    /// the call is repeated without `tokenType` (RN behaviour, older backends).
    /// - Parameters:
    ///   - authToken: user token. When nil, the stored token is used and one 401 is retried after a rotation.
    ///   - baseURL: REST base (ends in `/v1`). Defaults to `ChatConfig.baseUrl`.
    public static func registerPushSubscription(
        appId: String,
        registrationToken: String,
        tokenType: PushTokenType,
        deviceType: PushDeviceType,
        authToken: String? = nil,
        baseURL: URL? = nil
    ) async throws {
        let base = try await AppConfig.resolveBaseURL(baseURL)
        let url = subscriptionURL(base: base, appId: appId)
        let encoder = JSONEncoder()

        let first = try encoder.encode(SubscriptionBody(
            registrationToken: registrationToken,
            deviceType: deviceType.rawValue,
            tokenType: tokenType.rawValue
        ))
        let response = try await send(method: "POST", url: url, body: first, authToken: authToken)
        if (200..<300).contains(response.statusCode) {
            return
        }

        let canDowngrade = tokenType == .apns || tokenType == .fcm
        if canDowngrade, response.statusCode == 422, isUnknownFieldResponse(response.data) {
            let retryBody = try encoder.encode(LegacySubscriptionBody(
                registrationToken: registrationToken,
                deviceType: deviceType.rawValue
            ))
            let retry = try await send(method: "POST", url: url, body: retryBody, authToken: authToken)
            guard (200..<300).contains(retry.statusCode) else {
                throw PushAPIError.httpError(retry.statusCode, errorMessage(retry.data))
            }
            return
        }

        throw PushAPIError.httpError(response.statusCode, errorMessage(response.data))
    }

    /// Release a registered token on the backend (logout, or the token was replaced).
    /// A 404 on the subscription route falls back to `DELETE /v1/users/endpoints`.
    public static func releasePushSubscription(
        appId: String,
        registrationToken: String,
        authToken: String,
        baseURL: URL? = nil
    ) async throws {
        let base = try await AppConfig.resolveBaseURL(baseURL)
        let encoder = JSONEncoder()

        let primary = try await send(
            method: "DELETE",
            url: subscriptionURL(base: base, appId: appId),
            body: try encoder.encode(ReleaseBody(registrationToken: registrationToken)),
            authToken: authToken
        )
        if (200..<300).contains(primary.statusCode) {
            return
        }
        guard primary.statusCode == 404 else {
            throw PushAPIError.httpError(primary.statusCode, errorMessage(primary.data))
        }

        let fallback = try await send(
            method: "DELETE",
            url: base.appendingPathComponent("users").appendingPathComponent("endpoints"),
            body: try encoder.encode(EndpointBody(endpoint: registrationToken)),
            authToken: authToken
        )
        guard (200..<300).contains(fallback.statusCode) else {
            throw PushAPIError.httpError(fallback.statusCode, errorMessage(fallback.data))
        }
    }

    // MARK: - Gateway

    /// Subscribe through a push gateway (`pushNotifications.apiUrl`).
    /// `jid` is the user's full XMPP address (see `gatewayJID(username:host:)`).
    public static func subscribeToPushGateway(
        apiURL: String,
        registrationToken: String,
        deviceType: PushDeviceType,
        jid: String,
        projectName: String,
        authToken: String
    ) async throws {
        var trimmed = apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        guard let url = URL(string: trimmed + "/subscriptions") else {
            throw PushAPIError.networkError("Invalid push gateway URL: \(apiURL)")
        }
        let body = try JSONEncoder().encode(GatewayBody(
            projectName: projectName,
            registrationToken: registrationToken,
            deviceType: deviceType.rawValue,
            jid: jid
        ))
        let response = try await RESTTransport.send(
            method: "POST",
            url: url,
            authorization: "Bearer \(authToken)",
            body: body
        )
        guard (200..<300).contains(response.statusCode) else {
            throw PushAPIError.httpError(response.statusCode, errorMessage(response.data))
        }
    }

    /// `username` as a full JID on `host`. A value that already has `@` is returned as is.
    public static func gatewayJID(username: String, host: String) -> String {
        username.contains("@") ? username : "\(username)@\(host)"
    }

    // MARK: - Compatibility

    /// Register a token under an explicit device type (kept for source compatibility).
    /// New code should use `registerPushSubscription` or `PushNotificationManager.registerPushToken`.
    public static func registerPushToken(
        registrationToken: String,
        deviceType: PushDeviceType,
        appId: String? = nil,
        token: String? = nil,
        pushBaseURL: URL? = nil,
        authBaseURL: URL? = nil,
        didRefresh: Bool = false
    ) async throws {
        _ = didRefresh // retry is handled by `send` through `AuthRefresh`
        let config = await MainActor.run { ConfigStore.shared.config }
        let resolvedAppId = try await AppConfig.resolveAppId(appId ?? config.push?.appId)
        let base: URL?
        if let pushBaseURL {
            base = pushBaseURL
        } else if let configured = config.push?.pushBaseURL, let url = URL(string: configured) {
            base = url
        } else {
            base = try await AppConfig.resolveBaseURL(authBaseURL)
        }
        try await registerPushSubscription(
            appId: resolvedAppId,
            registrationToken: registrationToken,
            tokenType: PushTokenType.detect(registrationToken),
            deviceType: deviceType,
            authToken: token,
            baseURL: base
        )
    }

    // MARK: - Helpers

    static func subscriptionURL(base: URL, appId: String) -> URL {
        base.appendingPathComponent("push")
            .appendingPathComponent("subscription")
            .appendingPathComponent(appId)
    }

    /// Sends one request. With no explicit token the stored one is used, and a
    /// 401 triggers one rotation (`AuthRefresh`) and one retry.
    static func send(
        method: String,
        url: URL,
        body: Data,
        authToken: String?
    ) async throws -> RESTResponse {
        let explicit = authToken?.isEmpty == false ? authToken : nil
        let stored = await MainActor.run { UserStore.shared.token }
        guard let token = explicit ?? stored, !token.isEmpty else {
            throw PushAPIError.networkError("No user token available. Please login first.")
        }

        let response = try await RESTTransport.send(
            method: method, url: url, authorization: token, body: body
        )
        guard response.statusCode == 401, explicit == nil else {
            return response
        }
        let rotated = try await AuthRefresh.shared.refresh()
        return try await RESTTransport.send(
            method: method, url: url, authorization: rotated.token, body: body
        )
    }

    /// The backend answers 422 with `error` containing "not allowed" when a field is unknown to it.
    static func isUnknownFieldResponse(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? String else {
            return false
        }
        return error.range(of: "not allowed", options: .caseInsensitive) != nil
    }

    static func errorMessage(_ data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? String, !error.isEmpty {
            return error
        }
        return RESTTransport.bodyText(data)
    }
}

public enum PushAPIError: Error, LocalizedError {
    case httpError(Int, String)
    case decodeError(String)
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .httpError(let code, let body):
            return "HTTP \(code): \(body)"
        case .decodeError(let message):
            return "Decode error: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}
