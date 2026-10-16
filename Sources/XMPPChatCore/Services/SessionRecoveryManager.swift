//
//  SessionRecoveryManager.swift
//  XMPPChatCore
//
//  Bridges the "app returned to foreground after being backgrounded for a
//  long time" → "restore XMPP + REST session seamlessly" flow.
//
//  Steps taken when the app becomes active (matches what the user wants to
//  happen under the hood, invisibly):
//    1. If XMPP is already online → nothing to do.
//    2. Kick XMPP to reconnect with the credentials it already has in
//       memory (`XMPPClient.ensureConnected` → schedules a reconnect).
//       Wait for `isFullyConnected` up to a short timeout.
//    3. Still offline → the access token may have expired. Call
//       `AuthAPI.refreshToken` to swap the user token via the refresh
//       token, persist through `UserStore.updateTokens`, and let XMPP
//       try once more (XMPP password itself never changes on refresh).
//    4. If the refresh call itself fails (refresh token expired / server
//       rejected) → `LogoutManager.logout()`: the user is signed out,
//       caches cleared, hosting app shows its login screen. This matches
//       the "if refresh fails, drop the user" requirement.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
public final class SessionRecoveryManager {
    public static let shared = SessionRecoveryManager()

    /// Posted after a successful recovery (either a direct reconnect or a
    /// refresh-then-reconnect). Listeners like `RoomListViewModel` can use
    /// this to refresh their data — though `XMPPClientDidConnect` usually
    /// fires anyway.
    public static let sessionRecoveredNotification = Notification.Name("SessionRecovered")
    /// Posted right before `LogoutManager.logout()` runs on an irrecoverable
    /// session (refresh token rejected). Host app can use this to navigate
    /// to a login screen.
    public static let sessionUnrecoverableNotification = Notification.Name("SessionUnrecoverable")

    private var activeObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    private var inFlight = false

    private init() {
        #if canImport(UIKit)
        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.attemptRecoveryIfNeeded()
            }
        }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.attemptRecoveryIfNeeded()
            }
        }
        #endif
    }

    /// Call this explicitly (e.g. from a pull-to-refresh or after the app
    /// came back online from no-network state) to retry the same recovery
    /// flow. Safe to call repeatedly — concurrent invocations are suppressed.
    public func attemptRecoveryIfNeeded() async {
        guard !inFlight else { return }
        guard UserStore.shared.isAuthenticated else { return }
        guard let client = ClientRegistry.shared.getGlobalXMPPClient() else { return }

        inFlight = true
        defer { inFlight = false }

        // Fast path — `status` says online. But after a long background
        // suspend the WebSocket may be a zombie: TCP is dead, the OS hasn't
        // surfaced an error yet, and `status == .online` lies. Probe with a
        // real XMPP ping; if no pong in 2s, the socket is gone and we have
        // to force a hard reconnect.
        if client.isFullyConnected() {
            let alive = await client.pingProbe(timeout: 2.0)
            if alive {
                return
            }
            print("[SessionRecovery] ping probe timed out — socket is a zombie, forcing hard reconnect")
            await client.forceReconnect()
            if await waitForXMPPOnline(client: client, timeout: 8.0, kickReconnect: false) {
                NotificationCenter.default.post(
                    name: Self.sessionRecoveredNotification,
                    object: self
                )
                return
            }
            // Hard reconnect didn't come back in 8s — fall through to
            // refresh-token path below.
        }

        // Step 1: Try a plain XMPP reconnect with the existing credentials.
        if await waitForXMPPOnline(client: client, timeout: 8.0) {
            NotificationCenter.default.post(
                name: Self.sessionRecoveredNotification,
                object: self
            )
            return
        }

        // Step 2: XMPP didn't come back — probably access token is stale /
        // sessions on the server side expired. Try to rotate tokens.
        guard UserStore.shared.refreshToken?.isEmpty == false else {
            await forceLogout()
            return
        }

        // Rotation goes through `AuthRefresh` (single flight, persisted before return).
        do {
            _ = try await AuthRefresh.shared.refresh()
            print("[SessionRecovery] token refresh OK, retrying XMPP…")

            // Step 3: New access token is now in `UserStore`; XMPP password
            // itself doesn't change on refresh, so the existing client can
            // re-auth with the same credentials. Kick reconnect again.
            if await waitForXMPPOnline(client: client, timeout: 8.0) {
                NotificationCenter.default.post(
                    name: Self.sessionRecoveredNotification,
                    object: self
                )
                return
            }

            // XMPP still down after a valid refresh — DON'T force logout.
            // The user's credentials are valid; this is a transient network
            // issue. `XMPPClient`'s own background reconnect logic keeps
            // running, the chat-room screen stays mounted with a "no
            // connection" banner, and queued sends in `xmppStream` will
            // flush when the WebSocket comes back. Force-logging out here
            // used to kick users from an open chat into the room list on
            // any outage longer than ~16 seconds.
            print("[SessionRecovery] XMPP still offline after refresh — leaving client to keep retrying")
        } catch let fatal as RefreshFatalError {
            // `AuthRefresh` already ran the logout hook for a dead session.
            print("[SessionRecovery] refresh token rejected (\(fatal.code.rawValue)), session ended")
        } catch {
            // Network failures, 5xx and 401s without a known code leave the
            // session alone: the credentials may still be valid.
            print("[SessionRecovery] refresh failed (transient): \(error.localizedDescription), keeping session")
        }
    }

    private func waitForXMPPOnline(
        client: XMPPClient,
        timeout: TimeInterval,
        kickReconnect: Bool = true
    ) async -> Bool {
        // Poke the client's own reconnect logic if it's idle. `ensureConnected`
        // throws when not online, but its side-effect is to schedule a
        // reconnect which we then wait for below.
        //
        // The caller can pass `kickReconnect: false` when they've just kicked
        // the reconnect themselves (e.g. via `forceReconnect()` after a
        // failed ping probe) — calling `ensureConnected` on top of that
        // would schedule a duplicate reconnect and race with the first.
        if kickReconnect, !client.isFullyConnected() {
            _ = try? await client.ensureConnected(timeout: 2.0)
        }
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if client.isFullyConnected() {
                return true
            }
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
        }
        return client.isFullyConnected()
    }

    /// Ends the session: posts `sessionUnrecoverableNotification`, then logs out.
    func forceLogout() async {
        NotificationCenter.default.post(
            name: Self.sessionUnrecoverableNotification,
            object: self
        )
        await LogoutManager.shared.logout()
    }

    deinit {
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
        }
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
    }
}
