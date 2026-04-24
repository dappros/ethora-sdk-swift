//
//  UseLogout.swift
//  XMPPChatCore
//
//  Unified logout flow: disconnect XMPP, unsubscribe from push/mucsub,
//  clear caches and tokens. Idempotent — safe to call even when the
//  user is already logged out.
//

import Foundation

@MainActor
public final class LogoutManager {
    public static let shared = LogoutManager()
    private init() {}

    /// Logout options. Default is a full logout that keeps `ChatConfig`
    /// (baseUrl, appId, styling, etc.) — the hosting app usually wants to
    /// reuse its own settings after logout.
    public struct Options: Sendable {
        /// Tear down the XMPP connection.
        public var disconnectXMPP: Bool
        /// Reset push (FCM token, mucsub room subscriptions, the list of
        /// subscribed rooms in UserDefaults).
        public var resetPush: Bool
        /// Wipe tokens and the current user (UserStore + message cache).
        public var clearUser: Bool
        /// Clear rooms, pending heap, unread counters, pending push JID.
        public var clearCaches: Bool
        /// Reset `ChatConfig` to defaults. Usually NOT needed — the hosting
        /// app typically reuses the same API/XMPP settings on next login.
        public var resetConfig: Bool

        public init(
            disconnectXMPP: Bool = true,
            resetPush: Bool = true,
            clearUser: Bool = true,
            clearCaches: Bool = true,
            resetConfig: Bool = false
        ) {
            self.disconnectXMPP = disconnectXMPP
            self.resetPush = resetPush
            self.clearUser = clearUser
            self.clearCaches = clearCaches
            self.resetConfig = resetConfig
        }

        public static let `default` = Options()
    }

    /// Full logout.
    ///
    /// Order matters: push/mucsub are reset before tearing down XMPP (while
    /// the stream is still alive), then XMPP is disconnected, then stores
    /// and persistence are cleared.
    /// - Parameters:
    ///   - client: a specific `XMPPClient`. If nil, taken from `ClientRegistry`.
    ///   - options: fine-grained control over what to clear.
    public func logout(
        client: XMPPClient? = nil,
        options: Options = .default
    ) async {
        let target = client ?? ClientRegistry.shared.getGlobalXMPPClient()
        print("[Logout] start — disconnectXMPP=\(options.disconnectXMPP) resetPush=\(options.resetPush) clearUser=\(options.clearUser) clearCaches=\(options.clearCaches) resetConfig=\(options.resetConfig)")

        // 1. Push: clear FCM token, handles and drop the mucsub subscription
        //    cache in PushSubscriptionService. Done before disconnect so that
        //    any stop-subscribe can still flow through the live stream.
        if options.resetPush {
            await PushNotificationManager.shared.reset()
        }

        // 2. XMPP disconnect — graceful stream close.
        if options.disconnectXMPP, let target {
            await target.disconnect()
        }

        // 3. Release the global client reference — the next login will
        //    create a fresh `XMPPClient` and register it anew.
        ClientRegistry.shared.setGlobalXMPPClient(nil)

        // 4. Caches for rooms / messages / pending / notifications.
        //    `MessageHeapState` is an ObservableObject created by the
        //    hosting code; we don't have a global handle to it. Its
        //    instance dies together with its view-model during re-render
        //    after `isAuthenticated` flips.
        if options.clearCaches {
            RoomStore.shared.clearAll()
            MessageCache.shared.clearAll()
            // Unread/last-read keys are maintained by UseUnreadMessagesCounter
            // directly through UserDefaults — clear them here so they don't
            // leak between sessions of two different users.
            UserDefaults.standard.removeObject(forKey: "ethora_unread_counts")
            UserDefaults.standard.removeObject(forKey: "ethora_last_read")
            PendingNotificationJidStore.clearPendingJid()
        }

        // 5. Tokens and user data. UserStore.clearUser() itself calls
        //    MessageCache.clearAll() — harmless that step 4 already did it.
        if options.clearUser {
            UserStore.shared.clearUser()
        }

        // 6. Optional: reset config. Off by default.
        if options.resetConfig {
            ConfigStore.shared.reset()
        }

        print("[Logout] complete")
    }

    // MARK: - Legacy completion-based API

    /// Callback wrapper around `logout(client:options:)` — for hosting code
    /// that doesn't want async/await.
    public func logout(
        client: XMPPClient?,
        onCompletion: @escaping () -> Void
    ) {
        Task { @MainActor in
            await logout(client: client, options: .default)
            onCompletion()
        }
    }

    /// Asks for confirmation and, if confirmed, performs a full logout.
    public func logoutWithConfirmation(
        client: XMPPClient?,
        showConfirmation: @escaping (@escaping (Bool) -> Void) -> Void,
        onCompletion: @escaping () -> Void
    ) {
        showConfirmation { confirmed in
            guard confirmed else { return }
            self.logout(client: client, onCompletion: onCompletion)
        }
    }
}
