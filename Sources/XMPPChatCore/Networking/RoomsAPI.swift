//
//  RoomsAPI.swift
//  XMPPChatCore
//
//  Fetches rooms from Ethora HTTP API (mirrors src/networking/api-requests/rooms.api.ts)
//

import Foundation
import os.log

public struct RoomsAPI {
    public struct RoomsResponse: Codable {
        public let items: [ApiRoom]
    }

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
        // API call - no verbose logging
        
        // Get token from UserStore (must be on MainActor)
        let token = await MainActor.run {
            UserStore.shared.token
        }
        
        guard let token = token else {
            throw RoomsAPIError.networkError("No user token available. Please login first.")
        }
        
        let appIdToUse = appId ?? AppConfig.defaultAppId
        let url = baseURL.appendingPathComponent("chats/my")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue(appIdToUse, forHTTPHeaderField: "x-app-id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                // Handle 401 by refreshing token from UserStore
                if httpResponse.statusCode == 401 && !didRefresh {
                    
                    let refreshToken = await MainActor.run {
                        UserStore.shared.refreshToken
                    }
                    
                    guard let refreshToken = refreshToken else {
                        throw RoomsAPIError.httpError(401, "Token expired and no refresh token available")
                    }
                    
                    do {
                        let (newToken, newRefreshToken) = try await AuthAPI.refreshToken(
                            refreshToken: refreshToken,
                            baseURL: baseURL
                        )
                        
                        // Update UserStore with new tokens (must be on MainActor)
                        await MainActor.run {
                            UserStore.shared.updateTokens(token: newToken, refreshToken: newRefreshToken)
                        }
                        
                        // Retry with new token
                        return try await getRooms(
                            baseURL: baseURL,
                            appId: appIdToUse,
                            conferenceDomain: conferenceDomain,
                            didRefresh: true
                        )
                    } catch {
                        throw RoomsAPIError.httpError(401, "Token expired and refresh failed: \(error.localizedDescription)")
                    }
                }
                
                if !(200..<300).contains(httpResponse.statusCode) {
                    let errorBody = String(data: data, encoding: .utf8) ?? "<no body>"
                    throw RoomsAPIError.httpError(httpResponse.statusCode, errorBody)
                }
            }

            let decoder = JSONDecoder()
            // Use default keys - API response uses camelCase which matches our struct property names
            // Custom CodingKeys in structs will handle _id mapping
            decoder.keyDecodingStrategy = .useDefaultKeys
            decoder.dateDecodingStrategy = .iso8601  // For createdAt/updatedAt dates

            do {
                let roomsResponse = try decoder.decode(RoomsResponse.self, from: data)
                let rooms = roomsResponse.items.map { Room(apiRoom: $0, conferenceDomain: conferenceDomain) }
                return rooms
            } catch let decodeError {
                throw RoomsAPIError.decodeError(decodeError.localizedDescription)
            }
        } catch let urlError {
            throw RoomsAPIError.networkError(urlError.localizedDescription)
        }
    }
    
}

public enum RoomsAPIError: Error, LocalizedError {
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


