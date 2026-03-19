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

    static func performRequest<T: Codable>(
        url: URL,
        method: String,
        body: Codable? = nil,
        baseURL: URL,
        appId: String?,
        didRefresh: Bool
    ) async throws -> T {
        let token = await MainActor.run {
            UserStore.shared.token
        }
        
        guard let token = token else {
            throw RoomsAPIError.networkError("No user token available. Please login first.")
        }
        
        let appIdToUse = appId ?? AppConfig.defaultAppId
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue(appIdToUse, forHTTPHeaderField: "x-app-id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        if let body = body {
            request.httpBody = try AnyCodableEncoder().encode(body)
        }
        
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
                        
                        return try await performRequest(
                            url: url,
                            method: method,
                            body: body,
                            baseURL: baseURL,
                            appId: appId,
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
            
            if T.self == Bool.self {
                return true as! T
            }
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .useDefaultKeys
            decoder.dateDecodingStrategy = .iso8601
            
            return try decoder.decode(T.self, from: data)
        } catch let error as RoomsAPIError {
            throw error
        } catch {
            throw RoomsAPIError.networkError(error.localizedDescription)
        }
    }

    private struct AnyEncodable: Encodable {
        private let encodeClosure: (Encoder) throws -> Void
        
        init(_ wrapped: any Encodable) {
            self.encodeClosure = wrapped.encode(to:)
        }
        
        func encode(to encoder: Encoder) throws {
            try encodeClosure(encoder)
        }
    }

    private struct AnyCodableEncoder {
        func encode(_ value: Codable) throws -> Data {
            try JSONEncoder().encode(AnyEncodable(value))
        }
    }

    // MARK: - Room Operations
    // Methods getRooms, postRoom, postPrivateRoom, getRoomByName 
    // have been moved to RoomsAPI+Rooms.swift

    // MARK: - Member & Content Actions
    // Methods postReportRoom, postReportMessage, postAddRoomMember, 
    // deleteRoomMember, deleteRoom have been moved to RoomsAPI+Actions.swift
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
