//
//  E2EEManager.swift
//  XMPPChatCore
//
//  Glue between the OMEMO engine and the rest of the SDK, translated from
//  ethora-chat-component/src/e2ee/index.ts. Everything here is inert unless the host
//  app sets `config.e2ee.enabled` AND the backend marks the room `e2ee`. With the flag
//  off, no keys are generated and every stanza takes the plaintext path it always took.
//

import Foundation

/// Lock-protected copy of `config.e2ee.enabled`, readable from XMPP threads without
/// hopping to the main actor. ConfigStore keeps it in sync.
public enum E2EERuntime {
    private static let lock = NSLock()
    private static var enabledFlag = false

    /// True when the host app turned end-to-end encryption on.
    public static var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return enabledFlag
    }

    static func setEnabled(_ value: Bool) {
        lock.lock()
        enabledFlag = value
        lock.unlock()
    }
}

/// Owns the OMEMO engine for the connected account.
actor E2EEManager {

    static let shared = E2EEManager()

    private struct Live {
        let transport: E2EETransport
        let jid: String
    }

    private var live: Live?
    private var instance: E2EEOmemo?
    private var starting: Task<E2EEOmemo?, Never>?

    private init() {}

    /// Called once the XMPP session is up. Creates this device's keys and publishes them.
    func onOnline(transport: E2EETransport, jid: String) {
        live = Live(transport: transport, jid: E2EEOmemo.bare(jid))
        Task { _ = await self.ready() }
    }

    /// Drops the in-memory engine. Stored keys survive, so a later login resumes.
    func stop() {
        instance = nil
        starting?.cancel()
        starting = nil
        live = nil
    }

    /// The engine once it is usable. Waits out a start in progress, because the server
    /// starts pushing archived messages as soon as we join a room, which routinely beats
    /// our own key publish.
    func ready() async -> E2EEOmemo? {
        guard E2EERuntime.isEnabled else { return nil }
        if let instance, instance.jid == live?.jid { return instance }
        if let starting { return await starting.value }
        guard let live else { return nil }
        let task = Task<E2EEOmemo?, Never> {
            do {
                return try await E2EEOmemo.create(
                    transport: live.transport,
                    jid: live.jid,
                    store: E2EEKeychainStore(jid: live.jid)
                )
            } catch {
                // A failure must not take the chat down: plain rooms keep working, and in
                // encrypted ones the send path falls back to plaintext.
                print("[E2EE] could not start OMEMO: \(error)")
                return nil
            }
        }
        starting = task
        let result = await task.value
        starting = nil
        instance = result
        return result
    }

    /// True when the backend marked this room as end-to-end encrypted (and encryption is on).
    static func isE2eeRoom(_ roomJid: String) async -> Bool {
        guard E2EERuntime.isEnabled else { return false }
        let jid = E2EEOmemo.bare(roomJid)
        return await MainActor.run { RoomStore.shared.rooms[jid]?.e2ee == true }
    }

    /// Bare JIDs to encrypt for: every member of the room, from the REST member list.
    /// Somebody offline must still be able to read the message later.
    static func roomRecipients(_ roomJid: String, domain: String) async -> [String] {
        let jid = E2EEOmemo.bare(roomJid)
        let locals: [String] = await MainActor.run {
            (RoomStore.shared.rooms[jid]?.members ?? []).compactMap { member -> String? in
                let raw = member.xmppUsername ?? ""
                let local = raw.split(separator: "@", maxSplits: 1).first.map(String.init) ?? ""
                return local.isEmpty ? nil : local
            }
        }
        return locals.map { "\($0)@\(domain)".lowercased() }
    }

    /// The real bare JID behind a MUC `from`: `room@conference.host/nick` -> `nick@host`.
    /// This works because the SDK always joins with the account localpart as the nick.
    static func senderJid(fromMuc from: String, domain: String) -> String? {
        let parts = from.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[1].isEmpty, !domain.isEmpty else { return nil }
        return "\(parts[1])@\(domain)".lowercased()
    }

    /// Account domain taken from our own JID, e.g. "dappros.com".
    static func accountDomain(from jid: String?) -> String {
        guard let jid, let at = jid.firstIndex(of: "@") else { return "" }
        let afterAt = jid[jid.index(after: at)...]
        return String(afterAt.split(separator: "/", maxSplits: 1).first ?? "").lowercased()
    }
}
