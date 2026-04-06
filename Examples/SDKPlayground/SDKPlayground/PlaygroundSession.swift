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

    @Published var authMode: AuthMode = .emailPassword

    @Published var baseURLString: String = "https://api.ethoradev.com/v1"
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

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var isBusy: Bool = false
    @Published private(set) var lastError: String?
    /// Bump to force `ChatWrapperView` to recreate its view model after reconnect.
    @Published var chatInstanceId = UUID()

    private let userDefaultsKey = "sdk_playground_form_v1"

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
        if let m = AuthMode(rawValue: snap.authModeRaw) {
            authMode = m
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
            xmppConference: xmppConference
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
        return c
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
                    log.append("Auth: App token пустой — Authorization = встроенный dev app JWT из SDK.", level: .info)
                } else {
                    let header = AppConfig.appAuthorizationHeader(
                        fromPaste: tokenForAPI,
                        useEthoraJwtWordPrefix: useEthoraJwtWordPrefixForAppToken
                    )
                    let mode = useEthoraJwtWordPrefixForAppToken ? "JWT eyJ… (Ethora)" : "только eyJ… (без слова JWT)"
                    log.append("Auth: ваш App token — \(header.count) символов в Authorization, режим: \(mode).", level: .info)
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
            return "В App token попал только App ID (24 hex). Нужен полный JWT приложения (eyJ…), как appToken в web. Либо очистите App token — SDK подставит встроенный dev JWT."
        }
        guard AppConfig.compactThreePartJWT(fromAppTokenPaste: t) != nil else {
            return "App token не похож на JWT из трёх частей (xx.yy.zz). Проверьте .env: кавычки, переносы; нужен app JWT, не user token."
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

        enum CodingKeys: String, CodingKey {
            case authModeRaw, baseURLString, appToken, useEthoraJwtWordPrefixForAppToken, appId, jwtToken, email, password
            case xmppWebSocketURL, xmppHost, xmppConference
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
            xmppConference: String
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
        }
    }
}
