//
//  AccountAPI.swift
//  XMPPChatCore
//
//  Account endpoints for the settings screen. Same routes and bodies as web and RN:
//    PUT    /v1/users                  { "appLanguage" | "chatLanguage": "fr-CA" } (one field per call)
//    PUT    /v2/users/me/password      { "currentPassword", "newPassword" }
//    DELETE /v1/users
//    GET    /v1/users/exportData
//  The user token goes in `Authorization` as-is (no Bearer), as web and RN send it.
//

import Foundation

public enum AccountAPI {

    public enum ProfileLanguageField: String {
        case appLanguage
        case chatLanguage
    }

    public enum AccountError: LocalizedError, Equatable {
        case notSignedIn
        case invalidURL
        /// The server's reason, when it sent one (for example "The current password is not right").
        case server(status: Int, reason: String?)

        public var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Not signed in."
            case .invalidURL: return "The API base URL is not valid."
            case .server(let status, let reason):
                return reason ?? "HTTP \(status)"
            }
        }
    }

    // MARK: - Profile languages

    /// PUT /v1/users with a single language field. Returns false when the call fails.
    @discardableResult
    public static func updateProfileLanguage(field: ProfileLanguageField, value: String) async -> Bool {
        do {
            _ = try await send(method: "PUT", version: "v1", path: "users", body: [field.rawValue: value])
            return true
        } catch {
            return false
        }
    }

    // MARK: - Password

    /// PUT /v2/users/me/password. Throws `AccountError.server` with the server's reason.
    public static func changePassword(currentPassword: String, newPassword: String) async throws {
        _ = try await send(
            method: "PUT",
            version: "v2",
            path: "users/me/password",
            body: ["currentPassword": currentPassword, "newPassword": newPassword]
        )
    }

    // MARK: - Data

    /// DELETE /v1/users. The account is gone on success.
    public static func deleteAccount() async throws {
        _ = try await send(method: "DELETE", version: "v1", path: "users", body: nil)
    }

    /// GET /v1/users/exportData, the raw bytes of the export file.
    public static func exportMyData() async throws -> Data {
        try await send(method: "GET", version: "v1", path: "users/exportData", body: nil)
    }

    // MARK: - Transport

    /// Builds `{origin}/{version}/{path}` from the configured base URL, which
    /// ends in `/v1` (for example `https://api.chat.ethora.com/v1`). Only the
    /// trailing version segment is replaced, so a /v2 route resolves the same way.
    static func endpointURL(baseURL: URL, version: String, path: String) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        var segments = components?.path.split(separator: "/").map(String.init) ?? []
        if let last = segments.last, last == "v1" || last == "v2" {
            segments.removeLast()
        }
        segments.append(version)
        segments.append(contentsOf: path.split(separator: "/").map(String.init))
        components?.path = "/" + segments.joined(separator: "/")
        components?.query = nil
        return components?.url
    }

    @discardableResult
    private static func send(
        method: String,
        version: String,
        path: String,
        body: [String: String]?
    ) async throws -> Data {
        let token = await MainActor.run { UserStore.shared.token }
        guard let token = token, !token.isEmpty else { throw AccountError.notSignedIn }

        let baseURL = try await AppConfig.resolveBaseURL(nil)
        guard let url = endpointURL(baseURL: baseURL, version: version, path: path) else {
            throw AccountError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let appId = try? await AppConfig.resolveAppId(nil), !appId.isEmpty {
            request.setValue(appId, forHTTPHeaderField: "x-app-id")
        }
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw AccountError.server(status: status, reason: reason(from: data))
        }
        return data
    }

    /// The `message` or `error` field of a JSON error body, else the plain text.
    static func reason(from data: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["message", "error", "reason"] {
                if let text = object[key] as? String, !text.isEmpty { return text }
            }
        }
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty == false) ? text : nil
    }
}
