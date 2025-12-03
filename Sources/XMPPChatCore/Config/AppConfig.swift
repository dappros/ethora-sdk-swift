//
//  AppConfig.swift
//  XMPPChatCore
//
//  Global configuration values (app token, base URLs, etc.)
//

import Foundation

public enum AppConfig {
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
        return URL(string: "https://api.ethoradev.com/v1")!
    }
    
    /// Default XMPP settings (production, not dev)
    public static var defaultXMPPSettings: XMPPSettings {
        return XMPPSettings(
            devServer: "wss://xmpp.ethoradev.com:5443/ws",
            host: "xmpp.ethoradev.com",
            conference: "conference.xmpp.ethoradev.com"
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


