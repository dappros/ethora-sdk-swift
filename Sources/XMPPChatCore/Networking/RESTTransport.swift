//
//  RESTTransport.swift
//  XMPPChatCore
//
//  Minimal HTTP helper shared by the push, refresh and XMPP-token calls.
//  Sends the Authorization header exactly as given: the web and RN SDKs
//  send the raw user token (not "Bearer ...") to /v1/push and /v1/users.
//

import Foundation

struct RESTResponse {
    let statusCode: Int
    let data: Data
    /// Response headers with lower-cased names.
    let headers: [String: String]
}

enum RESTTransport {
    /// Session used by the auth and push calls. Tests replace it with a
    /// session whose protocol class answers without the network.
    static var session: URLSession = .shared

    static func send(
        method: String,
        url: URL,
        authorization: String?,
        body: Data?,
        extraHeaders: [String: String] = [:]
    ) async throws -> RESTResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let authorization, !authorization.isEmpty {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let k = key as? String, let v = value as? String {
                headers[k.lowercased()] = v
            }
        }
        return RESTResponse(statusCode: http.statusCode, data: data, headers: headers)
    }

    /// Text of a response body, for error messages.
    static func bodyText(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? "<no body>"
    }
}
