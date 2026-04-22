//
//  PlaygroundSession.swift
//  SDKPlayground
//

import Foundation
import SwiftUI
import XMPPChatCore

/// Holds playground connection state and applies env + auth into `ConfigStore` / `UserStore`.
@MainActor
final class PlaygroundSession: ObservableObject {
    enum AuthMode: String, CaseIterable, Identifiable {
        case jwtCustom = "JWT (custom token)"
        case emailPassword = "Email + password"

        var id: String { rawValue }
    }
    
    enum ConnectionPreset: String, CaseIterable, Identifiable {
        case ethoraDev = "Ethora Dev"
        case custom = "Custom"
        
        var id: String { rawValue }
    }
    
    enum UIPreset: String, CaseIterable, Identifiable {
        case light = "Light"
        case dark = "Dark"
        case custom = "Custom"
        
        var id: String { rawValue }
    }
    
    enum AppTheme: String, CaseIterable, Identifiable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"
        
        var id: String { rawValue }
    }

    @Published var authMode: AuthMode = .emailPassword
    @Published var connectionPreset: ConnectionPreset = .ethoraDev
    @Published var uiPreset: UIPreset = .light
    @Published var appTheme: AppTheme = .system

    @Published var baseURLString: String = "https://api.chat.ethora.com/v1"
    @Published var appToken: String = ""
    /// When `true`, login uses `Authorization: JWT eyJ…` (Ethora / web). When `false`, only `eyJ…` (no `JWT ` / no added `Bearer`).
    @Published var useEthoraJwtWordPrefixForAppToken: Bool = true
    @Published var appId: String = ""

    @Published var jwtToken: String = ""
    @Published var email: String = ""
    @Published var password: String = ""

    @Published var xmppWebSocketURL: String = ""
    @Published var xmppHost: String = ""
    @Published var xmppConference: String = ""
    @Published var useSingleChatMode: Bool = false
    @Published var singleChatRoomJID: String = ""
    
    @Published var primaryColorHex: String = "#5E3FDE"
    @Published var secondaryColorHex: String = "#E1E4FE"
    @Published var incomingMessageColorHex: String = "#F2F4F8"
    @Published var outgoingMessageColorHex: String = "#5E3FDE"
    @Published var incomingMessageTextColorHex: String = "#111827"
    @Published var outgoingMessageTextColorHex: String = "#FFFFFF"
    @Published var chatBackgroundColorHex: String = ""

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var isBusy: Bool = false
    @Published private(set) var lastError: String?
    /// Bump to force `ChatWrapperView` to recreate its view model after reconnect.
    @Published var chatInstanceId = UUID()

    private let userDefaultsKey = "sdk_playground_form_v1"
    
    var initialRoomJIDForChatWrapper: String? {
        guard useSingleChatMode else { return nil }
        return resolvedSingleRoomJID()
    }

    init() {
        loadFromDefaults()
    }

    func loadFromDefaults() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let snap = try? JSONDecoder().decode(FormSnapshot.self, from: data) else {
            return
        }
        baseURLString = snap.baseURLString
        appToken = snap.appToken
        appId = snap.appId
        jwtToken = snap.jwtToken
        email = snap.email
        password = snap.password
        xmppWebSocketURL = snap.xmppWebSocketURL
        xmppHost = snap.xmppHost
        xmppConference = snap.xmppConference
        useSingleChatMode = snap.useSingleChatMode
        singleChatRoomJID = snap.singleChatRoomJID
        primaryColorHex = snap.primaryColorHex
        secondaryColorHex = snap.secondaryColorHex
        incomingMessageColorHex = snap.incomingMessageColorHex
        outgoingMessageColorHex = snap.outgoingMessageColorHex
        incomingMessageTextColorHex = snap.incomingMessageTextColorHex
        outgoingMessageTextColorHex = snap.outgoingMessageTextColorHex
        chatBackgroundColorHex = snap.chatBackgroundColorHex
        if let m = AuthMode(rawValue: snap.authModeRaw) {
            authMode = m
        }
        if let preset = ConnectionPreset(rawValue: snap.connectionPresetRaw) {
            connectionPreset = preset
        }
        if let preset = UIPreset(rawValue: snap.uiPresetRaw) {
            uiPreset = preset
        }
        if let theme = AppTheme(rawValue: snap.appThemeRaw) {
            appTheme = theme
        }
    }

    func saveFormToDefaults() {
        let snap = FormSnapshot(
            authModeRaw: authMode.rawValue,
            baseURLString: baseURLString,
            appToken: appToken,
            useEthoraJwtWordPrefixForAppToken: useEthoraJwtWordPrefixForAppToken,
            appId: appId,
            jwtToken: jwtToken,
            email: email,
            password: password,
            xmppWebSocketURL: xmppWebSocketURL,
            xmppHost: xmppHost,
            xmppConference: xmppConference,
            useSingleChatMode: useSingleChatMode,
            singleChatRoomJID: singleChatRoomJID,
            connectionPresetRaw: connectionPreset.rawValue,
            uiPresetRaw: uiPreset.rawValue,
            appThemeRaw: appTheme.rawValue,
            primaryColorHex: primaryColorHex,
            secondaryColorHex: secondaryColorHex,
            incomingMessageColorHex: incomingMessageColorHex,
            outgoingMessageColorHex: outgoingMessageColorHex,
            incomingMessageTextColorHex: incomingMessageTextColorHex,
            outgoingMessageTextColorHex: outgoingMessageTextColorHex,
            chatBackgroundColorHex: chatBackgroundColorHex
        )
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    /// Builds merged `ChatConfig` from form (used by chat tab).
    func buildChatConfig() -> ChatConfig {
        var c = ChatConfig()
        let trimmedBase = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBase.isEmpty {
            c.baseUrl = trimmedBase
        }
        let trimmedApp = appId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedApp.isEmpty {
            c.appId = trimmedApp
        }
        let trimmedToken = appToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedToken.isEmpty {
            c.customAppToken = trimmedToken
        }
        let ws = xmppWebSocketURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = xmppHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let conf = xmppConference.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ws.isEmpty || !host.isEmpty || !conf.isEmpty {
            c.xmppSettings = XMPPSettings(
                xmppServerUrl: ws.isEmpty ? nil : ws,
                host: host.isEmpty ? nil : host,
                conference: conf.isEmpty ? nil : conf
            )
        }
        c.disableRooms = useSingleChatMode
        if useSingleChatMode {
            c.forceSetRoom = true
            c.setRoomJidInPath = true
        }
        c.colors = ChatColors(primary: normalizedHex(primaryColorHex), secondary: normalizedHex(secondaryColorHex))
        c.bubleMessage = MessageBubbleStyle(
            backgroundMessageUser: normalizedHex(outgoingMessageColorHex),
            backgroundMessage: normalizedHex(incomingMessageColorHex),
            colorUser: normalizedHex(outgoingMessageTextColorHex),
            color: normalizedHex(incomingMessageTextColorHex),
            borderRadius: 16
        )
        let bg = chatBackgroundColorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bg.isEmpty {
            c.backgroundChat = BackgroundChatConfig(color: normalizedHex(bg), image: nil)
        }
        return c
    }
    
    func applyConnectionPreset() {
        switch connectionPreset {
        case .ethoraDev:
            baseURLString = "https://api.chat.ethora.com/v1"
            xmppWebSocketURL = "wss://xmpp.chat.ethora.com/ws"
            xmppHost = "xmpp.chat.ethora.com"
            xmppConference = "conference.xmpp.chat.ethora.com"
        case .custom:
            break
        }
    }
    
    func applyUIPreset() {
        switch uiPreset {
        case .light:
            appTheme = .light
            primaryColorHex = "#5E3FDE"
            secondaryColorHex = "#E1E4FE"
            incomingMessageColorHex = "#F2F4F8"
            outgoingMessageColorHex = "#5E3FDE"
            incomingMessageTextColorHex = "#111827"
            outgoingMessageTextColorHex = "#FFFFFF"
            chatBackgroundColorHex = "#FFFFFF"
        case .dark:
            appTheme = .dark
            primaryColorHex = "#8B7BFF"
            secondaryColorHex = "#1F2937"
            incomingMessageColorHex = "#1F2937"
            outgoingMessageColorHex = "#6D5EF5"
            incomingMessageTextColorHex = "#E5E7EB"
            outgoingMessageTextColorHex = "#FFFFFF"
            chatBackgroundColorHex = "#0B1220"
        case .custom:
            break
        }
    }
    
    /// Applies Setup values from a JSON object pasted by user.
    /// Expected shape:
    /// {
    ///   "connectionProfile": "ethoraDev|custom",
    ///   "auth": { "mode": "email|jwt", "email": "", "password": "", "token": "" },
    ///   "api": { "baseUrl": "", "appToken": "", "appId": "", "useJwtPrefix": true },
    ///   "xmpp": { "webSocketUrl": "", "host": "", "conference": "" },
    ///   "chat": { "singleRoomMode": false, "roomJid": "" }
    /// }
    func applySetupJSONObject(_ rawJSON: String) throws {
        let trimmed = rawJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "PlaygroundSession", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "JSON is empty."
            ])
        }
        
        let data = Data(trimmed.utf8)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "PlaygroundSession", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "JSON root must be an object."
            ])
        }
        
        func string(_ dict: [String: Any], _ key: String) -> String? {
            (dict[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        func bool(_ dict: [String: Any], _ key: String) -> Bool? {
            if let v = dict[key] as? Bool { return v }
            if let s = dict[key] as? String {
                let x = s.lowercased()
                if x == "true" { return true }
                if x == "false" { return false }
            }
            return nil
        }
        
        if let profile = string(root, "connectionProfile")?.lowercased() {
            if profile.contains("ethora") || profile == "ethoradev" || profile == "default" {
                connectionPreset = .ethoraDev
                applyConnectionPreset()
            } else if profile == "custom" {
                connectionPreset = .custom
            }
        }
        
        if let auth = root["auth"] as? [String: Any] {
            if let mode = string(auth, "mode")?.lowercased() {
                if mode == "jwt" || mode == "jwtcustom" {
                    authMode = .jwtCustom
                } else if mode == "email" || mode == "emailpassword" {
                    authMode = .emailPassword
                }
            }
            if let token = string(auth, "token"), !token.isEmpty {
                jwtToken = token
            }
            if let mail = string(auth, "email"), !mail.isEmpty {
                email = mail
            }
            if let pass = string(auth, "password"), !pass.isEmpty {
                password = pass
            }
        }
        
        if let api = root["api"] as? [String: Any] {
            if let base = string(api, "baseUrl"), !base.isEmpty {
                baseURLString = base
            }
            if let token = string(api, "appToken") {
                appToken = token
            }
            if let id = string(api, "appId") {
                appId = id
            }
            if let prefix = bool(api, "useJwtPrefix") {
                useEthoraJwtWordPrefixForAppToken = prefix
            }
        }
        
        if let xmpp = root["xmpp"] as? [String: Any] {
            if let ws = string(xmpp, "webSocketUrl"), !ws.isEmpty {
                xmppWebSocketURL = ws
            }
            if let host = string(xmpp, "host"), !host.isEmpty {
                xmppHost = host
            }
            if let conf = string(xmpp, "conference"), !conf.isEmpty {
                xmppConference = conf
            }
        }
        
        if let chat = root["chat"] as? [String: Any] {
            if let single = bool(chat, "singleRoomMode") {
                useSingleChatMode = single
            }
            if let roomJid = string(chat, "roomJid") {
                singleChatRoomJID = roomJid
            }
        }
        
        // Compatibility aliases to match common config naming.
        if let disableRooms = bool(root, "disableRooms") {
            useSingleChatMode = disableRooms
        }
        if let initialRoom = string(root, "initialRoomJID"), !initialRoom.isEmpty {
            singleChatRoomJID = initialRoom
        }
    }

    func connect(log: PlaygroundLogStore) async {
        lastError = nil
        isBusy = true
        defer { isBusy = false }

        saveFormToDefaults()

        guard let baseURL = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              !baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastError = "Invalid Base URL."
            log.append("Connect failed: invalid Base URL.", level: .error)
            return
        }
        
        if useSingleChatMode && initialRoomJIDForChatWrapper == nil {
            lastError = "Single chat mode requires a Room JID."
            log.append("Connect failed: single chat mode enabled but Room JID is empty.", level: .error)
            return
        }

        let partial = buildChatConfig()
        ConfigStore.shared.mergeConfig(partial)

        let tokenForAPI = appToken.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            switch authMode {
            case .jwtCustom:
                let jwt = jwtToken.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !jwt.isEmpty else {
                    lastError = "Enter JWT (custom token)."
                    log.append("Connect failed: empty JWT.", level: .error)
                    return
                }
                log.append("Auth: POST /users/client (loginViaJwt)...", level: .info)
                let response = try await AuthAPI.loginViaJwt(clientToken: jwt, baseURL: baseURL)
                UserStore.shared.setUser(from: response)
                log.append("Auth: OK — user \(response.user.email ?? response.user.username ?? response.user._id)", level: .success)

            case .emailPassword:
                let em = email.trimmingCharacters(in: .whitespacesAndNewlines)
                let pw = password
                guard !em.isEmpty, !pw.isEmpty else {
                    lastError = "Enter email and password."
                    log.append("Connect failed: empty email/password.", level: .error)
                    return
                }
                log.append("Auth: POST /users/login-with-email...", level: .info)
                if tokenForAPI.isEmpty {
                    log.append("Auth: App token is empty — Authorization uses built-in SDK dev app JWT.", level: .info)
                } else {
                    let header = AppConfig.appAuthorizationHeader(
                        fromPaste: tokenForAPI,
                        useEthoraJwtWordPrefix: useEthoraJwtWordPrefixForAppToken
                    )
                    let mode = useEthoraJwtWordPrefixForAppToken ? "JWT eyJ… (Ethora)" : "raw eyJ… (without JWT word)"
                    log.append("Auth: custom App token — \(header.count) chars in Authorization, mode: \(mode).", level: .info)
                }
                let appTok = tokenForAPI.isEmpty ? AppConfig.appToken : tokenForAPI
                if let tokenHint = Self.emailLoginAppTokenValidationMessage(rawToken: tokenForAPI) {
                    lastError = tokenHint
                    log.append("Connect failed: \(tokenHint)", level: .error)
                    return
                }
                let response = try await AuthAPI.loginWithEmail(
                    email: em,
                    password: pw,
                    baseURL: baseURL,
                    appToken: appTok
                )
                UserStore.shared.setUser(from: response)
                log.append("Auth: OK — user \(response.user.email ?? response.user._id)", level: .success)
            }

            isConnected = true
            chatInstanceId = UUID()
            log.append("Session: connected — open Chat tab.", level: .success)
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastError = msg
            log.append("Connect failed: \(msg)", level: .error)
        }
    }

    func disconnect(log: PlaygroundLogStore) async {
        lastError = nil
        isBusy = true
        defer { isBusy = false }

        if let client = ClientRegistry.shared.getGlobalXMPPClient() {
            log.append("Disconnecting XMPP client...", level: .info)
            await client.disconnect()
        }
        ClientRegistry.shared.setGlobalXMPPClient(nil)
        UserStore.shared.clearUser()
        isConnected = false
        chatInstanceId = UUID()
        log.append("Disconnected — session cleared.", level: .info)
    }

    /// Web `loginEmail` sends only email/password; app is taken from `Authorization` app JWT. Catch common .env mistakes.
    private static func emailLoginAppTokenValidationMessage(rawToken: String) -> String? {
        let t = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        if t.range(of: "^[a-fA-F0-9]{24}$", options: .regularExpression) != nil {
            return "App token looks like App ID only (24 hex). A full app JWT (eyJ…) is required, as in web appToken. Or leave App token empty to use built-in SDK dev JWT."
        }
        guard AppConfig.compactThreePartJWT(fromAppTokenPaste: t) != nil else {
            return "App token is not a valid 3-part JWT (xx.yy.zz). Check .env quotes/newlines; app JWT is required, not a user token."
        }
        return nil
    }

    private struct FormSnapshot: Codable {
        var authModeRaw: String
        var baseURLString: String
        var appToken: String
        var useEthoraJwtWordPrefixForAppToken: Bool
        var appId: String
        var jwtToken: String
        var email: String
        var password: String
        var xmppWebSocketURL: String
        var xmppHost: String
        var xmppConference: String
        var useSingleChatMode: Bool
        var singleChatRoomJID: String
        var connectionPresetRaw: String
        var uiPresetRaw: String
        var appThemeRaw: String
        var primaryColorHex: String
        var secondaryColorHex: String
        var incomingMessageColorHex: String
        var outgoingMessageColorHex: String
        var incomingMessageTextColorHex: String
        var outgoingMessageTextColorHex: String
        var chatBackgroundColorHex: String

        enum CodingKeys: String, CodingKey {
            case authModeRaw, baseURLString, appToken, useEthoraJwtWordPrefixForAppToken, appId, jwtToken, email, password
            case xmppWebSocketURL, xmppHost, xmppConference
            case useSingleChatMode, singleChatRoomJID
            case connectionPresetRaw, uiPresetRaw, appThemeRaw
            case primaryColorHex, secondaryColorHex
            case incomingMessageColorHex, outgoingMessageColorHex
            case incomingMessageTextColorHex, outgoingMessageTextColorHex
            case chatBackgroundColorHex
        }

        init(
            authModeRaw: String,
            baseURLString: String,
            appToken: String,
            useEthoraJwtWordPrefixForAppToken: Bool,
            appId: String,
            jwtToken: String,
            email: String,
            password: String,
            xmppWebSocketURL: String,
            xmppHost: String,
            xmppConference: String,
            useSingleChatMode: Bool,
            singleChatRoomJID: String,
            connectionPresetRaw: String,
            uiPresetRaw: String,
            appThemeRaw: String,
            primaryColorHex: String,
            secondaryColorHex: String,
            incomingMessageColorHex: String,
            outgoingMessageColorHex: String,
            incomingMessageTextColorHex: String,
            outgoingMessageTextColorHex: String,
            chatBackgroundColorHex: String
        ) {
            self.authModeRaw = authModeRaw
            self.baseURLString = baseURLString
            self.appToken = appToken
            self.useEthoraJwtWordPrefixForAppToken = useEthoraJwtWordPrefixForAppToken
            self.appId = appId
            self.jwtToken = jwtToken
            self.email = email
            self.password = password
            self.xmppWebSocketURL = xmppWebSocketURL
            self.xmppHost = xmppHost
            self.xmppConference = xmppConference
            self.useSingleChatMode = useSingleChatMode
            self.singleChatRoomJID = singleChatRoomJID
            self.connectionPresetRaw = connectionPresetRaw
            self.uiPresetRaw = uiPresetRaw
            self.appThemeRaw = appThemeRaw
            self.primaryColorHex = primaryColorHex
            self.secondaryColorHex = secondaryColorHex
            self.incomingMessageColorHex = incomingMessageColorHex
            self.outgoingMessageColorHex = outgoingMessageColorHex
            self.incomingMessageTextColorHex = incomingMessageTextColorHex
            self.outgoingMessageTextColorHex = outgoingMessageTextColorHex
            self.chatBackgroundColorHex = chatBackgroundColorHex
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            authModeRaw = try c.decodeIfPresent(String.self, forKey: .authModeRaw)
                ?? AuthMode.emailPassword.rawValue
            baseURLString = try c.decodeIfPresent(String.self, forKey: .baseURLString) ?? ""
            appToken = try c.decodeIfPresent(String.self, forKey: .appToken) ?? ""
            useEthoraJwtWordPrefixForAppToken = try c.decodeIfPresent(Bool.self, forKey: .useEthoraJwtWordPrefixForAppToken) ?? true
            appId = try c.decodeIfPresent(String.self, forKey: .appId) ?? ""
            jwtToken = try c.decodeIfPresent(String.self, forKey: .jwtToken) ?? ""
            email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
            password = try c.decodeIfPresent(String.self, forKey: .password) ?? ""
            xmppWebSocketURL = try c.decodeIfPresent(String.self, forKey: .xmppWebSocketURL) ?? ""
            xmppHost = try c.decodeIfPresent(String.self, forKey: .xmppHost) ?? ""
            xmppConference = try c.decodeIfPresent(String.self, forKey: .xmppConference) ?? ""
            useSingleChatMode = try c.decodeIfPresent(Bool.self, forKey: .useSingleChatMode) ?? false
            singleChatRoomJID = try c.decodeIfPresent(String.self, forKey: .singleChatRoomJID) ?? ""
            connectionPresetRaw = try c.decodeIfPresent(String.self, forKey: .connectionPresetRaw) ?? ConnectionPreset.ethoraDev.rawValue
            uiPresetRaw = try c.decodeIfPresent(String.self, forKey: .uiPresetRaw) ?? UIPreset.light.rawValue
            appThemeRaw = try c.decodeIfPresent(String.self, forKey: .appThemeRaw) ?? AppTheme.system.rawValue
            primaryColorHex = try c.decodeIfPresent(String.self, forKey: .primaryColorHex) ?? "#5E3FDE"
            secondaryColorHex = try c.decodeIfPresent(String.self, forKey: .secondaryColorHex) ?? "#E1E4FE"
            incomingMessageColorHex = try c.decodeIfPresent(String.self, forKey: .incomingMessageColorHex) ?? "#F2F4F8"
            outgoingMessageColorHex = try c.decodeIfPresent(String.self, forKey: .outgoingMessageColorHex) ?? "#5E3FDE"
            incomingMessageTextColorHex = try c.decodeIfPresent(String.self, forKey: .incomingMessageTextColorHex) ?? "#111827"
            outgoingMessageTextColorHex = try c.decodeIfPresent(String.self, forKey: .outgoingMessageTextColorHex) ?? "#FFFFFF"
            chatBackgroundColorHex = try c.decodeIfPresent(String.self, forKey: .chatBackgroundColorHex) ?? ""
        }
    }
    
    private func normalizedHex(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "#000000" }
        return trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
    }
    
    private func resolvedSingleRoomJID() -> String? {
        let raw = singleChatRoomJID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if raw.contains("@") {
            return raw
        }
        let conference = xmppConference.trimmingCharacters(in: .whitespacesAndNewlines)
        if conference.isEmpty {
            return raw
        }
        return "\(raw)@\(conference)"
    }
}
