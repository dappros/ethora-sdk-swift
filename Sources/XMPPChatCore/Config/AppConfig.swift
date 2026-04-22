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

    /// Dev user JWT token (same as `defaultUser.token` in src/api.config.ts).
    /// Used by default `RoomListViewModel` initializer so rooms load without
    /// wiring a real login flow yet. Override via `ETHORA_DEV_USER_TOKEN` env.
    public static var devUserToken: String {
        return defaultUser.token ?? ""
    }
    
    /// Default appId (same as `defaultUser.appId` in src/api.config.ts)
    public static var defaultAppId: String {
        return "646cc8dc96d4a4dc8f7b2f2d"
    }
    
    /// Default base URL for API calls
    public static var defaultBaseURL: URL {
        return URL(string: "https://api.chat.ethora.com/v1")!
    }

    /// Default base URL for push registration API.
    /// Must match the REST API base that exposes `push/subscriptions/{appId}` (same as RN `apiClient` baseURL, e.g. `…/v1`).
    public static var defaultPushBaseURL: URL {
        return defaultBaseURL
    }
    
    /// Default XMPP settings (production, not dev)
    public static var defaultXMPPSettings: XMPPSettings {
        return XMPPSettings(
            devServer: "wss://xmpp.chat.ethora.com/ws",
            host: "xmpp.chat.ethora.com",
            conference: "conference.xmpp.chat.ethora.com"
        )
    }
    
    /// Default user object (same as `defaultUser` in src/api.config.ts).
    /// Contains all user data for testing: email, xmppPassword, token, etc.
    /// DO NOT USE IN PRODUCTION
    public static var defaultUser: User {
        return User(
            id: "65831a646edcd3cee0545757",
            name: "Raze Yuki",
            token: "JWT eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJkYXRhIjp7InVzZXJJZCI6IjY1ODMxYTY0NmVkY2QzY2VlMDU0NTc1NyIsImFwcElkIjoiNjQ2Y2M4ZGM5NmQ0YTRkYzhmN2IyZjJkIn0sImlhdCI6MTcxODI1OTMzNCwiZXhwIjoxNzE4MjYwMjM0fQ.-eG07yKkNL6sAFw_-xwBxjios6XtWF6n1MExphyg4W4",
            refreshToken: "JWT eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJkYXRhIjp7InVzZXJJZCI6IjY1ODMxYTY0NmVkY2QzY2VlMDU0NTc1NyIsImFwcElkIjoiNjQ2Y2M4ZGM5NmQ0YTRkYzhmN2IyZjJkIn0sImlhdCI6MTcxODI1OTMzNCwiZXhwIjoxNzE4ODY0MTM0fQ.Zs7_eLdefD3i6nEO1b_XbFZA_q9SWFKDghj8HqJ2fC0",
            walletAddress: "0x6816810a7Fe04FC9b800f9D11564C0e4aEC25D78",
            firstName: "Raze",
            lastName: "Yuki",
            email: "yukiraze9@gmail.com",
            profileImage: "https://lh3.googleusercontent.com/a/ACg8ocLPzhjmRoDe9ZXawhnZN3nd0eEhrqoKwRicJyM6q2z_=s96-c",
            xmppPassword: "HDC7qnWI16",
            xmppUsername: "yukiraze9@gmail.com",
            isProfileOpen: true,
            isAssetsOpen: true,
            isAgreeWithTerms: false
        )
    }
    
    /// Creates an XMPPClient initialized with defaultUser credentials
    /// (email as username, xmppPassword as password)
    public static func createDefaultXMPPClient(settings: XMPPSettings? = nil) -> XMPPClient {
        let user = defaultUser
        return XMPPClient(
            username: user.xmppUsername ?? user.email ?? "",
            password: user.xmppPassword ?? "",
            settings: settings
        )
    }
}

