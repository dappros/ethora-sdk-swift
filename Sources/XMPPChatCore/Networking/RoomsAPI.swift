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
    
    // MARK: - Create Room
    
    /// Create a new room
    /// POST /chats
    public static func postRoom(
        title: String,
        type: RoomType,
        description: String? = nil,
        picture: String? = nil,
        members: [String]? = nil,
        baseURL: URL = URL(string: "https://api.ethoradev.com/v1")!,
        appId: String? = nil,
        didRefresh: Bool = false
    ) async throws -> ApiRoom {
        let token = await MainActor.run {
            UserStore.shared.token
        }
        
        guard let token = token else {
            throw RoomsAPIError.networkError("No user token available. Please login first.")
        }
        
        let appIdToUse = appId ?? AppConfig.defaultAppId
        let url = baseURL.appendingPathComponent("chats")
        
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
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue(appIdToUse, forHTTPHeaderField: "x-app-id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
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
                        
                        await MainActor.run {
                            UserStore.shared.updateTokens(token: newToken, refreshToken: newRefreshToken)
                        }
                        
                        return try await postRoom(
                            title: title,
                            type: type,
                            description: description,
                            picture: picture,
                            members: members,
                            baseURL: baseURL,
                            appId: appIdToUse,
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
            
            struct PostRoomResponse: Codable {
                let result: ApiRoom
            }
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .useDefaultKeys
            let decodedResponse = try decoder.decode(PostRoomResponse.self, from: data)
            return decodedResponse.result
        } catch let urlError {
            throw RoomsAPIError.networkError(urlError.localizedDescription)
        }
    }
    
    // MARK: - Create Private Room
    
    /// Create a private room
    /// POST /chats/private
    public static func postPrivateRoom(
        username: String,
        title: String = "Private chat",
        baseURL: URL = URL(string: "https://api.ethoradev.com/v1")!,
        appId: String? = nil,
        didRefresh: Bool = false
    ) async throws -> ApiRoom {
        let token = await MainActor.run {
            UserStore.shared.token
        }
        
        guard let token = token else {
            throw RoomsAPIError.networkError("No user token available. Please login first.")
        }
        
        let appIdToUse = appId ?? AppConfig.defaultAppId
        let url = baseURL.appendingPathComponent("chats/private")
        
        struct PostPrivateRoomBody: Codable {
            let username: String
        }
        
        let body = PostPrivateRoomBody(username: username)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue(appIdToUse, forHTTPHeaderField: "x-app-id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
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
                        
                        await MainActor.run {
                            UserStore.shared.updateTokens(token: newToken, refreshToken: newRefreshToken)
                        }
                        
                        return try await postPrivateRoom(
                            username: username,
                            title: title,
                            baseURL: baseURL,
                            appId: appIdToUse,
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
            
            struct PostPrivateRoomResponse: Codable {
                let result: ApiRoom
            }
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .useDefaultKeys
            let decodedResponse = try decoder.decode(PostPrivateRoomResponse.self, from: data)
            return decodedResponse.result
        } catch let urlError {
            throw RoomsAPIError.networkError(urlError.localizedDescription)
        }
    }
    
    // MARK: - Get Room By Name
    
    /// Get room by name
    /// GET /chats/my/{chatName}
    public static func getRoomByName(
        chatName: String,
        baseURL: URL = URL(string: "https://api.ethoradev.com/v1")!,
        appId: String? = nil,
        didRefresh: Bool = false
    ) async throws -> ApiRoom {
        let token = await MainActor.run {
            UserStore.shared.token
        }
        
        guard let token = token else {
            throw RoomsAPIError.networkError("No user token available. Please login first.")
        }
        
        let appIdToUse = appId ?? AppConfig.defaultAppId
        let url = baseURL.appendingPathComponent("chats/my/\(chatName)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue(appIdToUse, forHTTPHeaderField: "x-app-id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
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
                        
                        await MainActor.run {
                            UserStore.shared.updateTokens(token: newToken, refreshToken: newRefreshToken)
                        }
                        
                        return try await getRoomByName(
                            chatName: chatName,
                            baseURL: baseURL,
                            appId: appIdToUse,
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
            decoder.keyDecodingStrategy = .useDefaultKeys
            let room = try decoder.decode(ApiRoom.self, from: data)
            return room
        } catch let urlError {
            throw RoomsAPIError.networkError(urlError.localizedDescription)
        }
    }
    
    // MARK: - Report Room
    
    /// Report a room
    /// POST /chats/reports/{chatName}
    public static func postReportRoom(
        chatName: String,
        category: String,
        text: String? = nil,
        baseURL: URL = URL(string: "https://api.ethoradev.com/v1")!,
        appId: String? = nil,
        didRefresh: Bool = false
    ) async throws -> Bool {
        let token = await MainActor.run {
            UserStore.shared.token
        }
        
        guard let token = token else {
            throw RoomsAPIError.networkError("No user token available. Please login first.")
        }
        
        let appIdToUse = appId ?? AppConfig.defaultAppId
        let url = baseURL.appendingPathComponent("chats/reports/\(chatName)")
        
        struct ReportRoomBody: Codable {
            let category: String
            let text: String?
        }
        
        let body = ReportRoomBody(category: category, text: text)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue(appIdToUse, forHTTPHeaderField: "x-app-id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
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
                        
                        await MainActor.run {
                            UserStore.shared.updateTokens(token: newToken, refreshToken: newRefreshToken)
                        }
                        
                        return try await postReportRoom(
                            chatName: chatName,
                            category: category,
                            text: text,
                            baseURL: baseURL,
                            appId: appIdToUse,
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
            
            return true
        } catch let urlError {
            throw RoomsAPIError.networkError(urlError.localizedDescription)
        }
    }
    
    // MARK: - Add Room Members
    
    /// Add members to a room
    /// POST /chats/users-access
    public static func postAddRoomMember(
        chatName: String,
        members: [String],
        baseURL: URL = URL(string: "https://api.ethoradev.com/v1")!,
        appId: String? = nil,
        didRefresh: Bool = false
    ) async throws -> [RoomMember] {
        let token = await MainActor.run {
            UserStore.shared.token
        }
        
        guard let token = token else {
            throw RoomsAPIError.networkError("No user token available. Please login first.")
        }
        
        let appIdToUse = appId ?? AppConfig.defaultAppId
        let url = baseURL.appendingPathComponent("chats/users-access")
        
        struct AddRoomMemberBody: Codable {
            let chatName: String
            let members: [String]
        }
        
        let body = AddRoomMemberBody(chatName: chatName, members: members)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue(appIdToUse, forHTTPHeaderField: "x-app-id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
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
                        
                        await MainActor.run {
                            UserStore.shared.updateTokens(token: newToken, refreshToken: newRefreshToken)
                        }
                        
                        return try await postAddRoomMember(
                            chatName: chatName,
                            members: members,
                            baseURL: baseURL,
                            appId: appIdToUse,
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
            
            struct AddRoomMemberResponse: Codable {
                let results: [RoomMember]
            }
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .useDefaultKeys
            let decodedResponse = try decoder.decode(AddRoomMemberResponse.self, from: data)
            return decodedResponse.results
        } catch let urlError {
            throw RoomsAPIError.networkError(urlError.localizedDescription)
        }
    }
    
    // MARK: - Delete Room Members
    
    /// Remove members from a room
    /// DELETE /chats/users-access
    public static func deleteRoomMember(
        chatName: String,
        members: [String],
        baseURL: URL = URL(string: "https://api.ethoradev.com/v1")!,
        appId: String? = nil,
        didRefresh: Bool = false
    ) async throws -> Bool {
        let token = await MainActor.run {
            UserStore.shared.token
        }
        
        guard let token = token else {
            throw RoomsAPIError.networkError("No user token available. Please login first.")
        }
        
        let appIdToUse = appId ?? AppConfig.defaultAppId
        let url = baseURL.appendingPathComponent("chats/users-access")
        
        struct DeleteRoomMemberBody: Codable {
            let chatName: String
            let members: [String]
        }
        
        let body = DeleteRoomMemberBody(chatName: chatName, members: members)
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue(appIdToUse, forHTTPHeaderField: "x-app-id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
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
                        
                        await MainActor.run {
                            UserStore.shared.updateTokens(token: newToken, refreshToken: newRefreshToken)
                        }
                        
                        return try await deleteRoomMember(
                            chatName: chatName,
                            members: members,
                            baseURL: baseURL,
                            appId: appIdToUse,
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
            
            return true
        } catch let urlError {
            throw RoomsAPIError.networkError(urlError.localizedDescription)
        }
    }
    
    // MARK: - Delete Room
    
    /// Delete a room
    /// DELETE /chats
    public static func deleteRoom(
        name: String,
        baseURL: URL = URL(string: "https://api.ethoradev.com/v1")!,
        appId: String? = nil,
        didRefresh: Bool = false
    ) async throws -> Bool {
        let token = await MainActor.run {
            UserStore.shared.token
        }
        
        guard let token = token else {
            throw RoomsAPIError.networkError("No user token available. Please login first.")
        }
        
        let appIdToUse = appId ?? AppConfig.defaultAppId
        let url = baseURL.appendingPathComponent("chats")
        
        struct DeleteRoomBody: Codable {
            let name: String
        }
        
        let body = DeleteRoomBody(name: name)
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue(appIdToUse, forHTTPHeaderField: "x-app-id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
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
                        
                        await MainActor.run {
                            UserStore.shared.updateTokens(token: newToken, refreshToken: newRefreshToken)
                        }
                        
                        return try await deleteRoom(
                            name: name,
                            baseURL: baseURL,
                            appId: appIdToUse,
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
            
            return true
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


