//
//  XMPPTokenAPI.swift
//  XMPPChatCore
//
//  Translated from src/networking/api-requests/xmppToken.api.ts
//

import Foundation

public enum XMPPTokenAPIError: Error, LocalizedError, Equatable {
    case httpError(Int, String)
    case missingPassword

    public var errorDescription: String? {
        switch self {
        case .httpError(let code, let body):
            return "HTTP \(code): \(body)"
        case .missingPassword:
            return "xmpp-token response did not contain xmppPassword"
        }
    }
}

public struct XMPPTokenAPI {
    private struct Response: Decodable {
        let success: Bool?
        let xmppPassword: String?
    }

    /// Mint a fresh XMPP password for the logged-in user.
    /// POST /users/xmpp-token with body `{}`, `Authorization` = the user token.
    /// Used only after a SASL `not-authorized`, the password is short-lived.
    public static func fetchXmppPassword(
        token: String,
        baseURL: URL? = nil
    ) async throws -> String {
        let resolvedBaseURL = try await AppConfig.resolveBaseURL(baseURL)
        let url = resolvedBaseURL.appendingPathComponent("users/xmpp-token")
        let response = try await RESTTransport.send(
            method: "POST",
            url: url,
            authorization: token,
            body: Data("{}".utf8)
        )
        guard (200..<300).contains(response.statusCode) else {
            throw XMPPTokenAPIError.httpError(response.statusCode, RESTTransport.bodyText(response.data))
        }
        let decoded = try JSONDecoder().decode(Response.self, from: response.data)
        guard let password = decoded.xmppPassword, !password.isEmpty else {
            throw XMPPTokenAPIError.missingPassword
        }
        return password
    }
}
