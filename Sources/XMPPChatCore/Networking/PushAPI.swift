//
//  PushAPI.swift
//  XMPPChatCore
//
//  Push notification registration API
//  Mirrors push/subscription/{appId}
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
    /// POST /push/subscription/{appId}
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
        
        // Final pushBaseURL: provided parameter > config.push.pushBaseURL > AppConfig.defaultPushBaseURL
        var finalPushBaseURL = pushBaseURL
        if finalPushBaseURL == nil, let configURL = config.push?.pushBaseURL {
            finalPushBaseURL = URL(string: configURL)
        }
        let pushURL = finalPushBaseURL ?? AppConfig.defaultPushBaseURL
        
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

        let url = pushURL
            .appendingPathComponent("push")
            .appendingPathComponent("subscription")
            .appendingPathComponent(finalAppId)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(authorizationHeaderValue(userToken), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body = PushSubscriptionBody(
            registrationToken: registrationToken,
            deviceType: deviceType.rawValue
        )

        request.httpBody = try JSONEncoder().encode(body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
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

                if !(200..<300).contains(httpResponse.statusCode) {
                    let errorBody = String(data: data, encoding: .utf8) ?? "<no body>"
                    throw PushAPIError.httpError(httpResponse.statusCode, errorBody)
                }
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
