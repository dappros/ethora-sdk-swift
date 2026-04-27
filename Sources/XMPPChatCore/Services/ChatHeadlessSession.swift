//
//  ChatHeadlessSession.swift
//  XMPPChatCore
//
//  Headless chat bootstrap — starts auth + XMPP + rooms sync without
//  mounting any UI. Host apps use this together with `UnreadStateBridge`
//  to drive a tab-bar/app-icon badge while the chat screen is closed.
//
//  Mirrors `useChatWrapperInit` in the React component but strips the
//  SwiftUI/`ChatWrapperView` coupling. The created `XMPPClient` is
//  registered with `ClientRegistry`, so a later `ChatWrapperView` mount
//  reuses the same socket — no duplicated presences/subscriptions.
//

import Foundation
import Combine

@MainActor
public final class ChatHeadlessSession: ObservableObject {
    public static let shared = ChatHeadlessSession()

    public enum Status: Equatable {
        case idle
        case authenticating
        case connecting
        case syncingRooms
        case ready
        case failed(String)

        public static func == (lhs: Status, rhs: Status) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle),
                 (.authenticating, .authenticating),
                 (.connecting, .connecting),
                 (.syncingRooms, .syncingRooms),
                 (.ready, .ready):
                return true
            case (.failed(let l), .failed(let r)):
                return l == r
            default:
                return false
            }
        }
    }

    public struct StartError: LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    @Published public private(set) var status: Status = .idle

    private var startTask: Task<Void, Never>?

    private init() {}

    /// Starts a headless chat session: auth → XMPP connect → rooms sync →
    /// per-room MUC presence → unread recompute → push attach.
    ///
    /// Idempotent: if a session is already running or ready, this is a
    /// no-op. If you need to reconfigure, call `stop()` first.
    public func start(config: ChatConfig? = nil) {
        switch status {
        case .ready, .authenticating, .connecting, .syncingRooms:
            return
        case .idle, .failed:
            break
        }

        if let config = config {
            ConfigStore.shared.mergeConfig(config)
        }

        startTask?.cancel()
        startTask = Task { [weak self] in
            await self?.run()
        }
    }

    /// Stops the headless session: disconnects the XMPP client and clears
    /// the global registry so the next `start()` (or `ChatWrapperView`
    /// mount) creates a fresh socket.
    ///
    /// Call on logout. Do not call while `ChatWrapperView` is on screen —
    /// it would yank the socket out from under the chat UI.
    public func stop() async {
        startTask?.cancel()
        startTask = nil

        if let client = ClientRegistry.shared.getGlobalXMPPClient() {
            await client.disconnect()
            ClientRegistry.shared.setGlobalXMPPClient(nil)
        }
        status = .idle
    }

    // MARK: - Pipeline

    private func run() async {
        let config = ConfigStore.shared.config

        status = .authenticating
        if !(await ensureAuthenticated(config: config)) {
            return
        }

        guard let user = UserStore.shared.currentUser,
              let xmppPassword = user.xmppPassword,
              !xmppPassword.isEmpty
        else {
            status = .failed("Missing XMPP credentials on user")
            return
        }

        let xmppHost = (config.xmppSettings?.host ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let xmppUsername = resolveXmppUsername(user: user, host: xmppHost)
        guard !xmppUsername.isEmpty else {
            status = .failed("Could not derive XMPP username")
            return
        }

        status = .connecting
        let client: XMPPClient
        if let existing = ClientRegistry.shared.getGlobalXMPPClient() {
            client = existing
        } else {
            client = XMPPClient(
                username: xmppUsername,
                password: xmppPassword,
                settings: config.xmppSettings
            )
            ClientRegistry.shared.setGlobalXMPPClient(client)
        }

        let connected = await waitUntilConnected(client: client, timeout: 15.0)
        if !connected {
            status = .failed("XMPP connect timeout")
            return
        }

        status = .syncingRooms
        do {
            try await syncRooms(config: config, client: client, user: user)
        } catch {
            status = .failed(error.localizedDescription)
            return
        }

        PushNotificationManager.shared.attachClient(client)
        await PushNotificationManager.shared.refreshRoomPushSubscriptions()

        status = .ready
    }

    private func ensureAuthenticated(config: ChatConfig) async -> Bool {
        if UserStore.shared.currentUser != nil {
            return true
        }

        if config.jwtLogin?.enabled == true {
            let ok = await UserStore.performJWTLoginIfConfigured()
            if ok { return true }
        }

        if let userLogin = config.userLogin,
           userLogin.enabled,
           let configuredUser = userLogin.user {
            UserStore.shared.currentUser = configuredUser
            UserStore.shared.token = configuredUser.token
            UserStore.shared.refreshToken = configuredUser.refreshToken
            UserStore.shared.isAuthenticated = !((configuredUser.token ?? "").isEmpty)
            return true
        }

        status = .failed("No authentication method configured")
        return false
    }

    private func resolveXmppUsername(user: User, host: String) -> String {
        if let username = user.xmppUsername?.trimmingCharacters(in: .whitespacesAndNewlines),
           !username.isEmpty {
            let local = username.components(separatedBy: "@").first ?? username
            return host.isEmpty ? local : "\(local)@\(host)"
        }
        if let wallet = user.walletAddress, !wallet.isEmpty {
            let local = walletToUsername(wallet)
            return host.isEmpty ? local : "\(local)@\(host)"
        }
        let local = (user.email ?? "").components(separatedBy: "@").first ?? (user.email ?? "")
        return host.isEmpty ? local : "\(local)@\(host)"
    }

    private func waitUntilConnected(client: XMPPClient, timeout: TimeInterval) async -> Bool {
        if client.isFullyConnected() { return true }
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if Task.isCancelled { return false }
            if client.isFullyConnected() { return true }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return client.isFullyConnected()
    }

    private func syncRooms(config: ChatConfig, client: XMPPClient, user: User) async throws {
        let baseURLString = (config.baseUrl ?? "https://api.chat.ethora.com/v1")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: baseURLString), !baseURLString.isEmpty else {
            throw StartError(message: "Invalid baseUrl")
        }
        let conferenceDomain = config.xmppSettings?.conference ?? "conference.xmpp.chat.ethora.com"

        let rooms = try await RoomsAPI.getRooms(
            baseURL: baseURL,
            appId: config.appId ?? AppConfig.defaultAppId,
            conferenceDomain: conferenceDomain
        )

        for room in rooms {
            RoomStore.shared.addRoomFromApi(room)
        }

        // MUC presence per room — required for the server to deliver live
        // broadcasts to this client. Without this step, mucsub-only mode
        // produces only wrapped self-echoes and unread never moves.
        let roomJIDs = rooms.map { $0.jid }
        if !roomJIDs.isEmpty {
            await client.sendPresenceToAllRooms(roomJIDs: roomJIDs)
        }

        let currentUserLocal = currentUserLocalPart(user: user)
        RoomStore.shared.recomputeAllUnread(currentUserLocal: currentUserLocal)
    }

    private func currentUserLocalPart(user: User) -> String {
        if let username = user.xmppUsername, !username.isEmpty {
            return username.components(separatedBy: "@").first ?? username
        }
        if let wallet = user.walletAddress, !wallet.isEmpty {
            return walletToUsername(wallet)
        }
        if let email = user.email, !email.isEmpty {
            return email.components(separatedBy: "@").first ?? email
        }
        return ""
    }
}
