//
//  PushNotificationManager.swift
//  XMPPChatCore
//
//  Push lifecycle for the host app. Translated from RN
//  src/services/pushRegistration.ts (token slots, release on logout,
//  gateway mode, host token hook) and pushSubscriptionService.ts.
//
//  The host passes its device token (`registerPushToken`), or returns it from
//  `pushNotifications.getPushTokens`. The SDK has no Firebase dependency.
//  Registration waits until a session exists, and room subscriptions run
//  only when push is enabled.
//

import Foundation

@MainActor
public final class PushNotificationManager {
    public static let shared = PushNotificationManager()

    /// Posted by `handlePushPayload` with `userInfo["roomJid"]` (bare JID).
    /// A mounted chat list can open the room straight away. The JID is also
    /// stored as pending (`PendingNotificationJidStore`), so a list that mounts later still finds it.
    public static let openRoomNotification = Notification.Name("EthoraPushOpenRoom")

    public enum RegisterOutcome: Equatable {
        /// Registered with the backend (or gateway).
        case registered
        /// Token held. Registration waits for a signed-in session.
        case deferred
        /// Push is off by config. Token held, nothing sent.
        case disabled
    }

    /// Two slots, as RN: `apns-voip` lives apart from the chat token.
    private enum Slot: Hashable {
        case chat
        case voip
    }

    private struct HeldToken {
        let token: String
        let tokenType: PushTokenType
    }

    private struct ServerRegistration {
        let token: String
        let tokenType: PushTokenType
        let appId: String
        let xmppUsername: String
        let gateway: Bool
    }

    private struct Session {
        let authToken: String
        let appId: String
        let xmppUsername: String
        let projectName: String
        let gatewayURL: String
        let xmppHost: String
        let pushDisabled: Bool

        var isGateway: Bool { !gatewayURL.isEmpty }

        var isReady: Bool {
            guard !authToken.isEmpty else { return false }
            return isGateway ? (!xmppUsername.isEmpty && !projectName.isEmpty) : !appId.isEmpty
        }
    }

    private var held: [Slot: HeldToken] = [:]
    private var registered: [Slot: ServerRegistration] = [:]
    /// Registration passes run one after another, so each sees the latest held tokens.
    private var registrationChain: Task<Void, Never>?
    private var hookIdentity: String?
    private weak var client: XMPPClient?

    private init() {}

    // MARK: - Public API

    /// Hand the device push token to the SDK. Works with an APNs token or an FCM token.
    /// The token type is detected from its shape unless given.
    /// - Returns: `.registered`, `.deferred` (no session yet) or `.disabled` (push off by config).
    /// - Throws: the backend's refusal, or a network error. The token stays held either way.
    @discardableResult
    public func registerPushToken(
        _ token: String,
        tokenType: PushTokenType? = nil
    ) async throws -> RegisterOutcome {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PushAPIError.networkError("registerPushToken: token must be a non-empty string")
        }
        hold(trimmed, tokenType: tokenType)

        let session = readSession()
        if session.pushDisabled {
            return .disabled
        }
        guard session.isReady else {
            return .deferred
        }
        try await registerNow()
        return .registered
    }

    /// Remove a token from the device and from the backend.
    /// - Parameter tokenType: only that slot. Nil means both slots.
    public func unregisterPushToken(tokenType: PushTokenType? = nil) async throws {
        let slots: [Slot] = tokenType.map { [slot(for: $0)] } ?? [.chat, .voip]
        var toRelease: [ServerRegistration] = []
        for slot in slots {
            held[slot] = nil
            if let current = registered[slot] {
                registered[slot] = nil
                toRelease.append(current)
            }
        }
        let session = readSession()
        guard !session.authToken.isEmpty else { return }
        for entry in toRelease where !entry.gateway {
            try await releaseOnServer(entry, authToken: session.authToken)
        }
    }

    /// Hand a tapped push payload to the SDK. Stores the room as pending, posts
    /// `openRoomNotification`, and returns the bare room JID. Returns nil when
    /// the payload names no room. Call it from the host's notification-tap handler.
    @discardableResult
    public func handlePushPayload(_ userInfo: [AnyHashable: Any]) -> String? {
        guard let raw = RemoteNotificationPayload.roomJid(from: userInfo) else { return nil }
        let bare = raw.components(separatedBy: "/").first ?? raw
        PendingNotificationJidStore.store(jid: bare)
        NotificationCenter.default.post(
            name: Self.openRoomNotification,
            object: nil,
            userInfo: ["roomJid": bare]
        )
        return bare
    }

    /// Bind the live XMPP client, used for room subscriptions.
    public func attachClient(_ client: XMPPClient) {
        self.client = client
        Task { await self.refreshRoomPushSubscriptions() }
    }

    /// Hand a device token over with the live client. Kept for source compatibility.
    public func configure(fcmToken: String, client: XMPPClient) {
        self.client = client
        hold(fcmToken, tokenType: nil)
        Task { await self.refreshRoomPushSubscriptions() }
    }

    /// Replace the device token. Kept for source compatibility.
    public func updateFCMToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        hold(trimmed, tokenType: nil)
        Task { await self.refreshRoomPushSubscriptions() }
    }

    /// Runs the host token hook, registers pending tokens, then subscribes every
    /// loaded room over MUCSub. Called after the room list loads and on attach.
    public func refreshRoomPushSubscriptions() async {
        guard !readSession().pushDisabled else {
            print("[Push] refreshRoomPushSubscriptions skipped: push disabled")
            return
        }
        await runTokenHookIfNeeded()
        do {
            try await registerNow()
        } catch {
            print("[Push] registration failed: \(error.localizedDescription)")
        }

        guard let client, client.checkOnline() else {
            print("[Push] refreshRoomPushSubscriptions skipped: client offline")
            return
        }
        let roomJIDs = Array(RoomStore.shared.rooms.keys)
        guard !roomJIDs.isEmpty else { return }
        await PushSubscriptionService.shared.subscribeToRooms(client: client, roomJIDs: roomJIDs)
    }

    /// MUCSub subscribe for one room that appeared after the sweep (created in the app, or an invite).
    public func subscribeRoomForPush(_ roomJID: String) async {
        guard !readSession().pushDisabled, let client, client.checkOnline() else { return }
        _ = await PushSubscriptionService.shared.subscribeToRoom(client: client, roomJID: roomJID)
    }

    /// Logout: releases the registrations on the backend, then forgets the tokens and the client.
    /// `LogoutManager` awaits it before the session is cleared.
    public func reset() async {
        await releasePushRegistration()
        held.removeAll()
        registered.removeAll()
        hookIdentity = nil
        client = nil
        await PushSubscriptionService.shared.reset()
    }

    /// Releases the server-side registrations (keeps the held tokens).
    /// Best effort, never throws.
    public func releasePushRegistration() async {
        let current = Array(registered.values)
        registered.removeAll()
        let token = UserStore.shared.token ?? ""
        guard !token.isEmpty else { return }
        for entry in current where !entry.gateway {
            do {
                try await releaseOnServer(entry, authToken: token)
            } catch {
                print("[Push] releasing the token on logout failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Registration

    private func hold(_ token: String, tokenType: PushTokenType?) {
        let resolved = tokenType ?? PushTokenType.detect(token)
        held[slot(for: resolved)] = HeldToken(token: token, tokenType: resolved)
    }

    private func slot(for tokenType: PushTokenType) -> Slot {
        tokenType == .apnsVoip ? .voip : .chat
    }

    /// Serialises registration passes. Each pass waits for the previous one,
    /// so a token held meanwhile is never missed.
    private func registerNow() async throws {
        let previous = registrationChain
        let pass = Task<Void, Error> {
            _ = await previous?.value
            try await self.runRegistrationPass()
        }
        registrationChain = Task { _ = try? await pass.value }
        try await pass.value
    }

    private func runRegistrationPass() async throws {
        let session = readSession()
        if session.pushDisabled {
            await releasePushRegistration()
            return
        }
        guard session.isReady else { return }

        var firstError: Error?
        for slot in [Slot.chat, .voip] {
            guard let token = held[slot], !isRegistered(slot, token, session) else { continue }
            do {
                // Same user, new token: release the old one first.
                if let previous = registered[slot], previous.xmppUsername == session.xmppUsername {
                    registered[slot] = nil
                    if !previous.gateway {
                        try? await releaseOnServer(previous, authToken: session.authToken)
                    }
                }
                try await register(token, slot: slot, session: session)
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError {
            throw firstError
        }
    }

    private func isRegistered(_ slot: Slot, _ token: HeldToken, _ session: Session) -> Bool {
        guard let current = registered[slot] else { return false }
        return current.token == token.token
            && current.tokenType == token.tokenType
            && current.gateway == session.isGateway
            && current.appId == session.appId
            && current.xmppUsername == session.xmppUsername
    }

    private func register(_ token: HeldToken, slot: Slot, session: Session) async throws {
        if session.isGateway {
            guard !session.projectName.isEmpty else {
                throw PushAPIError.networkError("projectName is required when pushNotifications.apiUrl is set")
            }
            guard !session.xmppHost.isEmpty || session.xmppUsername.contains("@") else {
                throw PushAPIError.networkError("xmppSettings.host is required to build the gateway jid")
            }
            try await PushAPI.subscribeToPushGateway(
                apiURL: session.gatewayURL,
                registrationToken: token.token,
                deviceType: .ios,
                jid: PushAPI.gatewayJID(username: session.xmppUsername, host: session.xmppHost),
                projectName: session.projectName,
                authToken: session.authToken
            )
        } else {
            try await PushAPI.registerPushSubscription(
                appId: session.appId,
                registrationToken: token.token,
                tokenType: token.tokenType,
                deviceType: .ios
            )
        }
        registered[slot] = ServerRegistration(
            token: token.token,
            tokenType: token.tokenType,
            appId: session.appId,
            xmppUsername: session.xmppUsername,
            gateway: session.isGateway
        )
        print("[Push] \(token.tokenType.rawValue) token registered\(session.isGateway ? " (gateway)" : " for app \(session.appId)")")
    }

    private func releaseOnServer(_ entry: ServerRegistration, authToken: String) async throws {
        try await PushAPI.releasePushSubscription(
            appId: entry.appId,
            registrationToken: entry.token,
            authToken: authToken
        )
    }

    /// Host token hook, asked once per signed-in identity.
    private func runTokenHookIfNeeded() async {
        guard let hook = ConfigStore.shared.config.pushNotifications?.getPushTokens else { return }
        let session = readSession()
        let identity = session.xmppUsername.isEmpty ? session.appId : session.xmppUsername
        guard !identity.isEmpty, hookIdentity != identity else { return }
        hookIdentity = identity

        let entries = await hook() ?? []
        for entry in entries {
            let token = entry.token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { continue }
            hold(token, tokenType: entry.tokenType)
        }
    }

    private func readSession() -> Session {
        let config = ConfigStore.shared.config
        let user = UserStore.shared.currentUser
        let username = [user?.xmppUsername, user?.walletAddress]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        let pushEnabled = config.pushNotifications?.enabled ?? config.push?.enabled ?? true
        return Session(
            authToken: UserStore.shared.token ?? "",
            appId: (config.push?.appId ?? config.appId ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            xmppUsername: username,
            projectName: (config.projectName ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            gatewayURL: (config.pushNotifications?.apiUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            xmppHost: (config.xmppSettings?.host ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            pushDisabled: !pushEnabled
        )
    }
}
