//
//  AppConfig.swift
//  XMPPChatCore
//
//  Global configuration values (app token, base URLs, etc.)
//

import Foundation

public enum AppConfig {
    /// Normalizes the value used as `Authorization` on Ethora app-scoped REST calls.
    ///
    /// **What this does / does not do:**
    /// - Does **not** add a `Bearer` OAuth prefix to app tokens. If the user pasted `Bearer …`, it is stripped
    ///   and the remainder is normalized (same as web accidentally pasting OAuth style).
    /// - If the value already starts with **`JWT `** (Ethora app token style, same as `api.config` web), it is left
    ///   as that scheme — only cleaning whitespace inside the JWT.
    /// - If the value is a raw **`eyJ…`** JWT (common in `.env`), **`JWT `** is prepended — this is **not** Bearer;
    ///   it is the literal prefix Ethora’s REST layer expects for app JWTs (see `api/swagger.js` for
    ///   `/users/login-with-email`).
    ///
    /// - Parameter raw: User-provided app token, or empty to fall back to ``appToken``.
    ///
    /// Handles: surrounding `'`/`"`, UTF-8 BOM, mistaken `Bearer …`, line breaks inside the JWT.
    public static func normalizedAppAuthorizationHeader(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.replacingOccurrences(of: "\u{FEFF}", with: "")
        // Strip one or more layers of quotes from .env lines like APP_TOKEN="JWT eyJ..."
        while t.count >= 2 {
            let f = t.first!, l = t.last!
            if (f == "\"" && l == "\"") || (f == "'" && l == "'") {
                t = String(t.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            break
        }
        if t.isEmpty { return appToken }
        if t.lowercased().hasPrefix("bearer ") {
            let inner = String(t.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizedAppAuthorizationHeader(inner)
        }
        func jwtBodyWithoutInnerWhitespace(_ s: String) -> String {
            s.filter { !$0.isWhitespace }
        }
        let upper = t.uppercased()
        if upper.hasPrefix("JWT ") {
            let rest = jwtBodyWithoutInnerWhitespace(String(t.dropFirst(4)))
            return rest.isEmpty ? appToken : "JWT " + rest
        }
        if t.hasPrefix("eyJ") {
            return "JWT " + jwtBodyWithoutInnerWhitespace(t)
        }
        // Rare: spaces/newlines only inside a raw three-part token
        let compact = jwtBodyWithoutInnerWhitespace(t)
        if compact.hasPrefix("eyJ"), compact.split(separator: ".", omittingEmptySubsequences: false).count == 3 {
            return "JWT " + compact
        }
        return t
    }

    /// Extracts the three JWT segments (`xx.yy.zz`) after cleaning a pasted value (quotes, BOM, optional `Bearer` / `JWT `).
    /// Does **not** add `Bearer` or `JWT ` — used when the server expects a raw JWT in `Authorization`.
    public static func compactThreePartJWT(fromAppTokenPaste raw: String) -> String? {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.replacingOccurrences(of: "\u{FEFF}", with: "")
        while t.count >= 2 {
            let f = t.first!, l = t.last!
            if (f == "\"" && l == "\"") || (f == "'" && l == "'") {
                t = String(t.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            break
        }
        if t.isEmpty { return nil }
        if t.lowercased().hasPrefix("bearer ") {
            let inner = String(t.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
            return compactThreePartJWT(fromAppTokenPaste: inner)
        }
        func strip(_ s: String) -> String { s.filter { !$0.isWhitespace } }
        let upper = t.uppercased()
        let body: String
        if upper.hasPrefix("JWT ") {
            body = strip(String(t.dropFirst(4)))
        } else {
            body = strip(t)
        }
        if body.isEmpty { return nil }
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        return body
    }

    /// Builds the `Authorization` value for an app token pasted by the user.
    /// - `useEthoraJwtWordPrefix: true` — same as ``normalizedAppAuthorizationHeader(_:)`` (`JWT eyJ…`, Ethora public API).
    /// - `useEthoraJwtWordPrefix: false` — only `eyJ…` (no leading `JWT ` / no `Bearer` added).
    public static func appAuthorizationHeader(fromPaste raw: String, useEthoraJwtWordPrefix: Bool) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return appToken }
        if useEthoraJwtWordPrefix {
            return normalizedAppAuthorizationHeader(raw)
        }
        if let core = compactThreePartJWT(fromAppTokenPaste: raw) {
            return core
        }
        return normalizedAppAuthorizationHeader(raw)
    }

    /// Ethora appToken used when calling auth endpoints (same as `src/api.config.ts appToken`).
    ///
    /// It is read from the `ETHORA_APP_TOKEN` environment variable if present,
    /// otherwise falls back to the bundled development token.
    public static var appToken: String {
        if let fromEnv = ProcessInfo.processInfo.environment["ETHORA_APP_TOKEN"],
           !fromEnv.isEmpty {
            return fromEnv
        }

        // Fallback dev token – DO NOT USE IN PRODUCTION
        return """
JWT eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJkYXRhIjp7ImlzVXNlckRhdGFFbmNyeXB0ZWQiOmZhbHNlLCJwYXJlbnRBcHBJZCI6bnVsbCwiaXNBbGxvd2VkTmV3QXBwQ3JlYXRlIjp0cnVlLCJpc0Jhc2VBcHAiOnRydWUsIl9pZCI6IjY0NmNjOGRjOTZkNGE0ZGM4ZjdiMmYyZCIsImRpc3BsYXlOYW1lIjoiRXRob3JhIiwiZG9tYWluTmFtZSI6ImV0aG9yYSIsImNyZWF0b3JJZCI6IjY0NmNjOGQzOTZkNGE0ZGM4ZjdiMmYyNSIsInVzZXJzQ2FuRnJlZSI6dHJ1ZSwiZGVmYXVsdEFjY2Vzc0Fzc2V0c09wZW4iOnRydWUsImRlZmF1bHRBY2Nlc3NQcm9maWxlT3BlbiI6dHJ1ZSwiYnVuZGxlSWQiOiJjb20uZXRob3JhIiwicHJpbWFyeUNvbG9yIjoiIzAwM0U5QyIsInNlY29uZGFyeUNvbG9yIjoiIzI3NzVFQSIsImNvaW5TeW1ib2wiOiJFVE8iLCJjb2luTmFtZSI6IkV0aG9yYSBDb2luIiwiUkVBQ1RfQVBQX0ZJUkVCQVNFX0FQSV9LRVkiOiJBSXphU3lEUWRrdnZ4S0t4NC1XcmpMUW9ZZjA4R0ZBUmdpX3FPNGciLCJSRUFDVF9BUFBfRklSRUJBU0VfQVVUSF9ET01BSU4iOiJldGhvcmEtNjY4ZTkuZmlyZWJhc2VhcHAuY29tIiwiUkVBQ1RfQVBQX0ZJUkVCQVNFX1BST0pFQ1RfSUQiOiJldGhvcmEtNjY4ZTkiLCJSRUFDVF9BUFBfRklSRUJBU0VfU1RPUkFHRV9CVUNLRVQiOiJldGhvcmEtNjY4ZTkuYXBwc3BvdC5jb20iLCJSRUFDVF9BUFBfRklSRUJBU0VfTUVTU0FHSU5HX1NFTkRFUl9JRCI6Ijk3MjkzMzQ3MDA1NCIsIlJFQUNUX0FQUF9GSVJFQkFTRV9BUFBfSUQiOiIxOjk3MjkzMzQ3MDA1NDp3ZWI6ZDQ2ODJlNzZlZjAyZmQ5YjljZGFhNyIsIlJFQUNUX0FQUF9GSVJFQkFTRV9NRUFTVVJNRU5UX0lEIjoiRy1XSE03WFJaNEM4IiwiUkVBQ1RfQVBQX1NUUklQRV9QVUJMSVNIQUJMRV9LRVkiOiIiLCJSRUFDVF9BUFBfU1RSSVBFX1NFQ1JFVF9LRVkiOiIiLCJjcmVhdGVkQXQiOiIyMDIzLTA1LTIzVDE0OjA4OjI4LjEzNloiLCJ1cGRhdGVkQXQiOiIyMDIzLTA1LTIzVDE0OjA4OjI4LjEzNloiLCJfX3YiOjB9LCJpYXQiOjE2ODQ4NTA5MjV9.-IqNVMsf8GyS9Z-_yuNW7hpSmejajjAy-W0J8TadRIM
"""
    }

    // MARK: - Required configuration accessors
    //
    // The SDK ships with NO hardcoded backend defaults — endpoints
    // (`baseUrl`, `xmppSettings`) and `appId` MUST be supplied by the
    // host application via `ConfigStore.shared.mergeConfig(_:)` before
    // mounting chat or starting `ChatHeadlessSession`. The accessors
    // below throw `ConfigError` when a value is missing so the caller
    // can surface a clear failure instead of silently falling back to
    // an unrelated server.

    /// Returns the host's REST base URL.
    /// - Throws: `ConfigError.missingBaseURL` if `ChatConfig.baseUrl`
    ///   is `nil` or empty, `ConfigError.invalidBaseURL` if the value
    ///   does not parse as a `URL`.
    @MainActor
    public static func requireBaseURL() throws -> URL {
        let raw = ConfigStore.shared.config.baseUrl?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { throw ConfigError.missingBaseURL }
        guard let url = URL(string: raw) else {
            throw ConfigError.invalidBaseURL(raw)
        }
        return url
    }

    /// Returns the host's push REST base URL.
    /// Falls back to `requireBaseURL()` since push registration uses
    /// the same REST root in this SDK.
    @MainActor
    public static func requirePushBaseURL() throws -> URL {
        return try requireBaseURL()
    }

    /// Returns the host's XMPP transport settings.
    /// - Throws: `ConfigError.missingXMPPSettings` if
    ///   `ChatConfig.xmppSettings` is `nil` or has an empty
    ///   `host`/`conference`/`devServer`.
    @MainActor
    public static func requireXMPPSettings() throws -> XMPPSettings {
        guard let settings = ConfigStore.shared.config.xmppSettings else {
            throw ConfigError.missingXMPPSettings
        }
        let host = settings.host?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let conference = settings.conference?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let devServer = settings.devServer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !host.isEmpty, !conference.isEmpty, !devServer.isEmpty else {
            throw ConfigError.missingXMPPSettings
        }
        return settings
    }

    /// Async helper for callers that aren't on the main actor.
    /// Resolves `provided` if non-nil, otherwise reads from
    /// `ConfigStore` on the main actor.
    public static func resolveBaseURL(_ provided: URL? = nil) async throws -> URL {
        if let provided = provided { return provided }
        return try await MainActor.run { try requireBaseURL() }
    }

    /// Async helper — same as `resolveBaseURL(_:)` but for `appId`.
    public static func resolveAppId(_ provided: String? = nil) async throws -> String {
        if let provided = provided?.trimmingCharacters(in: .whitespacesAndNewlines), !provided.isEmpty {
            return provided
        }
        return try await MainActor.run { try requireAppId() }
    }

    /// MainActor-only synchronous variant of `resolveConferenceDomain(_:)`.
    /// Use this when the caller is already on the main actor and would
    /// rather avoid hopping back through `MainActor.run`.
    @MainActor
    public static func resolveConferenceDomainSync(_ provided: String? = nil) throws -> String {
        if let provided = provided?.trimmingCharacters(in: .whitespacesAndNewlines), !provided.isEmpty {
            return provided
        }
        let settings = try requireXMPPSettings()
        guard let conference = settings.conference?.trimmingCharacters(in: .whitespacesAndNewlines),
              !conference.isEmpty else {
            throw ConfigError.missingXMPPSettings
        }
        return conference
    }

    /// Async helper — resolves the XMPP conference domain.
    /// If `provided` is non-empty it is returned as is; otherwise the
    /// value is read from `ChatConfig.xmppSettings.conference` on the
    /// main actor. Throws `ConfigError.missingXMPPSettings` if none is
    /// configured.
    public static func resolveConferenceDomain(_ provided: String? = nil) async throws -> String {
        if let provided = provided?.trimmingCharacters(in: .whitespacesAndNewlines), !provided.isEmpty {
            return provided
        }
        let settings = try await MainActor.run { try requireXMPPSettings() }
        guard let conference = settings.conference?.trimmingCharacters(in: .whitespacesAndNewlines),
              !conference.isEmpty else {
            throw ConfigError.missingXMPPSettings
        }
        return conference
    }

    /// Returns the host's `appId`.
    /// - Throws: `ConfigError.missingAppId` if `ChatConfig.appId` is
    ///   missing or empty.
    @MainActor
    public static func requireAppId() throws -> String {
        let raw = ConfigStore.shared.config.appId?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { throw ConfigError.missingAppId }
        return raw
    }
}

