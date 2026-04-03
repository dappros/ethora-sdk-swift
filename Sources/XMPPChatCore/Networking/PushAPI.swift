//
//  PushAPI.swift
//  XMPPChatCore
//
//  Push notification registration API
//  Mirrors RN/Kotlin push subscriptions flow
//

import Foundation

public enum PushDeviceType: String, Codable {
    case ios
    case android
    case web
}

public struct PushAPI {
    private struct PushSubscriptionBody: Codable {
        let registrationToken: String
        let deviceType: String
    }

    /// Register device push token
    /// POST /push/subscriptions/{appId} (fallback: /push/subscription/{appId})
    /// - Parameters:
    ///   - registrationToken: FCM/APNs token
    ///   - deviceType: Platform identifier (ios/android/web)
    ///   - appId: App ID to register under
    ///   - token: Optional user token override (defaults to UserStore token)
    ///   - pushBaseURL: Push API base URL
    ///   - authBaseURL: Auth API base URL for refresh
    ///   - didRefresh: Internal flag to avoid refresh loops
    public static func registerPushToken(
        registrationToken: String,
        deviceType: PushDeviceType,
        appId: String? = nil,
        token: String? = nil,
        pushBaseURL: URL? = nil,
        authBaseURL: URL? = nil,
        didRefresh: Bool = false
    ) async throws {
        // Use provided values or defaults from config
        let config = await MainActor.run { ConfigStore.shared.config }
        
        // Final appId: provided parameter > config.push.appId > AppConfig.defaultAppId
        let finalAppId = appId ?? config.push?.appId ?? AppConfig.defaultAppId
        
        // Push registration lives on the main API (`…/v1/push/subscriptions/...`), same as RN — not a separate push host.
        let apiBaseFromConfig: URL = {
            if let s = config.baseUrl, let u = URL(string: s), !s.isEmpty { return u }
            return AppConfig.defaultBaseURL
        }()

        // Final pushBaseURL: explicit override > config.push.pushBaseURL > Chat API baseUrl
        var finalPushBaseURL = pushBaseURL
        if finalPushBaseURL == nil, let configURL = config.push?.pushBaseURL, let u = URL(string: configURL) {
            finalPushBaseURL = u
        }
        let pushURL = finalPushBaseURL ?? apiBaseFromConfig
        
        // Final authBaseURL: provided parameter > config.baseUrl > AppConfig.defaultBaseURL
        var finalAuthBaseURL = authBaseURL
        if finalAuthBaseURL == nil, let configAuthURL = config.baseUrl {
            finalAuthBaseURL = URL(string: configAuthURL)
        }
        let authURL = finalAuthBaseURL ?? AppConfig.defaultBaseURL

        let storedToken = await MainActor.run { UserStore.shared.token }
        let userToken = token ?? storedToken

        guard let userToken = userToken, !userToken.isEmpty else {
            throw PushAPIError.networkError("No user token available. Please login first.")
        }

        let body = PushSubscriptionBody(
            registrationToken: registrationToken,
            deviceType: deviceType.rawValue
        )
        let bodyData = try JSONEncoder().encode(body)
        let candidateURLs: [URL] = [
            pushURL
                .appendingPathComponent("push")
                .appendingPathComponent("subscriptions")
                .appendingPathComponent(finalAppId),
            pushURL
                .appendingPathComponent("push")
                .appendingPathComponent("subscription")
                .appendingPathComponent(finalAppId)
        ]

        do {
            var lastHTTPError: PushAPIError?
            for url in candidateURLs {
                print("[PushAPI] registering token at \(url.absoluteString)")
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue(authorizationHeaderValue(userToken), forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.httpBody = bodyData

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    continue
                }

                if httpResponse.statusCode == 401 && !didRefresh {
                    let refreshToken = await MainActor.run { UserStore.shared.refreshToken }

                    guard let refreshToken = refreshToken else {
                        throw PushAPIError.httpError(401, "Token expired and no refresh token available")
                    }

                    do {
                        let (newToken, newRefreshToken) = try await AuthAPI.refreshToken(
                            refreshToken: refreshToken,
                            baseURL: authURL
                        )

                        await MainActor.run {
                            UserStore.shared.updateTokens(token: newToken, refreshToken: newRefreshToken)
                        }

                        return try await registerPushToken(
                            registrationToken: registrationToken,
                            deviceType: deviceType,
                            appId: finalAppId,
                            token: newToken,
                            pushBaseURL: pushURL,
                            authBaseURL: authURL,
                            didRefresh: true
                        )
                    } catch {
                        throw PushAPIError.httpError(401, "Token expired and refresh failed: \(error.localizedDescription)")
                    }
                }

                if (200..<300).contains(httpResponse.statusCode) {
                    print("[PushAPI] registration success status=\(httpResponse.statusCode)")
                    return
                }

                let errorBody = String(data: data, encoding: .utf8) ?? "<no body>"
                lastHTTPError = .httpError(httpResponse.statusCode, errorBody)
            }

            if let lastHTTPError {
                throw lastHTTPError
            }
        } catch let urlError {
            throw PushAPIError.networkError(urlError.localizedDescription)
        }
    }

    private static func authorizationHeaderValue(_ token: String) -> String {
        if token.lowercased().hasPrefix("bearer ") {
            return token
        }
        return "Bearer \(token)"
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
