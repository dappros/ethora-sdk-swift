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

        // Fast path — already online.
        if client.isFullyConnected() {
            return
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
        guard let refreshToken = UserStore.shared.refreshToken,
              !refreshToken.isEmpty else {
            await forceLogout()
            return
        }

        let baseURL: URL
        do {
            baseURL = try AppConfig.requireBaseURL()
        } catch {
            print("[SessionRecovery] cannot refresh token: \(error.localizedDescription)")
            return
        }

        do {
            let (newToken, newRefreshToken) = try await AuthAPI.refreshToken(
                refreshToken: refreshToken,
                baseURL: baseURL
            )
            UserStore.shared.updateTokens(token: newToken, refreshToken: newRefreshToken)
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

            // XMPP still down after a valid refresh — treat as unrecoverable.
            await forceLogout()
        } catch {
            print("[SessionRecovery] refresh token failed: \(error.localizedDescription)")
            await forceLogout()
        }
    }

    private func waitForXMPPOnline(client: XMPPClient, timeout: TimeInterval) async -> Bool {
        // Poke the client's own reconnect logic if it's idle. `ensureConnected`
        // throws when not online, but its side-effect is to schedule a
        // reconnect which we then wait for below.
        if !client.isFullyConnected() {
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

    private func forceLogout() async {
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
