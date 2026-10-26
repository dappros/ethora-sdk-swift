//
//  XMPPCredentialRecovery.swift
//  XMPPChatCore
//
//  Recovers XMPP credentials after a SASL `not-authorized`. Ported from the
//  web `credentialsProvider` (src/context/xmppProvider.tsx) and RN
//  `recoverXmppCredentials` (src/networking/xmppCredentials.ts).
//
//  Order: a forced session rotation when `refreshTokens` is enabled (it
//  re-issues the XMPP password), then `POST /users/xmpp-token` (single
//  flight), then the stored credentials as a last resort.
//

import Foundation

@MainActor
public final class XMPPCredentialRecovery {
    public static let shared = XMPPCredentialRecovery()

    /// Forced session rotation. Tests replace it.
    var refreshSession: () async -> RefreshResult? = {
        await AuthRefresh.shared.refreshQuietly(force: true)
    }

    /// `POST /users/xmpp-token`. Tests replace it.
    var fetchPassword: (String) async throws -> String = { token in
        try await XMPPTokenAPI.fetchXmppPassword(token: token)
    }

    private var inflightFetch: Task<String?, Never>?

    private init() {}

    /// Fresh XMPP credentials for the next connect attempt, or nil when the
    /// session holds none at all. Never throws.
    public func recover() async -> (username: String, password: String)? {
        let user = UserStore.shared.currentUser
        let username = user?.xmppUsername?.isEmpty == false
            ? user?.xmppUsername ?? ""
            : user?.walletAddress ?? ""

        if ConfigStore.shared.config.refreshTokens?.enabled == true,
           let rotated = await refreshSession(),
           let password = rotated.xmppPassword, !password.isEmpty {
            return (username, password)
        }

        if let fresh = await fetchFreshPassword() {
            return (username, fresh)
        }

        if let stored = UserStore.shared.currentUser?.xmppPassword, !stored.isEmpty {
            return (username, stored)
        }
        return nil
    }

    /// Single-flight `POST /users/xmpp-token`. Several reconnect paths can ask
    /// at once; they share one request. Stores the result on success.
    func fetchFreshPassword() async -> String? {
        if let inflightFetch {
            return await inflightFetch.value
        }
        let task = Task<String?, Never> { [fetchPassword] in
            guard let token = UserStore.shared.token, !token.isEmpty else { return nil }
            do {
                let password = try await fetchPassword(token)
                UserStore.shared.setXmppPassword(password)
                return password
            } catch {
                print("[XMPPCredentialRecovery] xmpp-token failed: \(error.localizedDescription)")
                return nil
            }
        }
        inflightFetch = task
        let value = await task.value
        if inflightFetch == task {
            inflightFetch = nil
        }
        return value
    }
}
