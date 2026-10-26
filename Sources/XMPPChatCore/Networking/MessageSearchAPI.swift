//
//  MessageSearchAPI.swift
//  XMPPChatCore
//
//  Translated from src/networking/api-requests/messageSearch.api.ts
//  GET /v2/apps/{appId}/messages/search
//

import Foundation

public enum MessageSearchAPIError: Error, LocalizedError {
    case noAppId
    case noToken
    case httpError(Int, String)
    case decodeError(String)
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .noAppId: return "Message search needs an appId in the chat config."
        case .noToken: return "No user token available. Please login first."
        case .httpError(let code, let body): return "Message search failed (\(code)): \(body)"
        case .decodeError(let message): return "Message search response could not be read: \(message)"
        case .networkError(let message): return "Message search network error: \(message)"
        }
    }
}

public struct MessageSearchAPI {

    /// The v2 endpoint for an app. Like `apiClient.ts`, a trailing `/v1` or
    /// `/v2` is stripped from the configured base URL before the path is added.
    public static func searchEndpoint(baseURL: URL, appId: String) -> URL? {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        if let range = base.range(of: "/v[12]$", options: [.regularExpression, .caseInsensitive]) {
            base.removeSubrange(range)
        }
        let escapedAppId = appId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? appId
        return URL(string: "\(base)/v2/apps/\(escapedAppId)/messages/search")
    }

    /// Searches the archive. The server restricts a user token to the chats
    /// that user can see, so no client-side privacy filter is needed.
    /// A 401 refreshes the user token once and retries, as the REST helpers do.
    public static func search(
        _ query: MessageSearchQuery,
        baseURL: URL? = nil,
        appId: String? = nil,
        didRefresh: Bool = false
    ) async throws -> MessageSearchPage {
        let resolvedBaseURL = try await AppConfig.resolveBaseURL(baseURL)
        let resolvedAppId: String
        do {
            resolvedAppId = try await AppConfig.resolveAppId(appId)
        } catch {
            throw MessageSearchAPIError.noAppId
        }
        guard let endpoint = searchEndpoint(baseURL: resolvedBaseURL, appId: resolvedAppId),
              var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw MessageSearchAPIError.networkError("Invalid search URL")
        }
        components.queryItems = query.queryItems
        guard let url = components.url else {
            throw MessageSearchAPIError.networkError("Invalid search URL")
        }

        let token = await MainActor.run { UserStore.shared.token }
        guard let token, !token.isEmpty else { throw MessageSearchAPIError.noToken }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // No Bearer prefix: web sends the user token as-is.
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw MessageSearchAPIError.networkError(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 && !didRefresh {
                let refreshToken = await MainActor.run { UserStore.shared.refreshToken }
                guard let refreshToken else {
                    throw MessageSearchAPIError.httpError(401, "Token expired and no refresh token available")
                }
                do {
                    let refreshed = try await AuthAPI.refreshToken(refreshToken: refreshToken, baseURL: resolvedBaseURL)
                    await MainActor.run {
                        UserStore.shared.updateTokens(token: refreshed.token, refreshToken: refreshed.refreshToken)
                    }
                } catch {
                    throw MessageSearchAPIError.httpError(401, "Token expired and refresh failed: \(error.localizedDescription)")
                }
                return try await search(query, baseURL: resolvedBaseURL, appId: resolvedAppId, didRefresh: true)
            }
            guard (200..<300).contains(http.statusCode) else {
                throw MessageSearchAPIError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "<no body>")
            }
        }

        do {
            return try MessageSearchParser.parsePage(data: data, offset: query.offset, limit: query.limit)
        } catch {
            throw MessageSearchAPIError.decodeError(error.localizedDescription)
        }
    }
}
