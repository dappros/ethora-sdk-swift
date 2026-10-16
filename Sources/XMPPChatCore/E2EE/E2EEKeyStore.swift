//
//  E2EEKeyStore.swift
//  XMPPChatCore
//
//  Key-value persistence for OMEMO keys, sessions and decrypted messages, plus the
//  transport seam the OMEMO engine uses to talk to the XMPP server. Private keys live
//  in the Keychain (the web keeps them in IndexedDB; the Keychain is the iOS equivalent
//  and keeps keys out of backups). Tests use the in-memory store.
//

import Foundation
import Security

/// Storage for OMEMO state. Values are Codable and stored as JSON.
protocol E2EEKeyStore: AnyObject {
    func get<T: Decodable>(_ key: String, as type: T.Type) -> T?
    func set<T: Encodable>(_ key: String, _ value: T)
    func delete(_ key: String)
}

/// Sends and receives the stanzas OMEMO needs. XMPPClient conforms.
protocol E2EETransport: AnyObject {
    /// Sends an IQ, assigns its id, and returns the matching result. Throws
    /// `E2EEIQError` for an error response or a timeout.
    func e2eeSendIQ(_ iq: XMPPStanza) async throws -> XMPPStanza
    /// Sends a stanza without waiting for a reply.
    func e2eeSend(_ stanza: XMPPStanza)
}

/// An IQ error, carrying the XMPP stanza-error condition (e.g. "item-not-found").
struct E2EEIQError: Error, LocalizedError, Equatable {
    let condition: String?

    var errorDescription: String? {
        "XMPP IQ error: \(condition ?? "unknown")"
    }
}

/// In-memory store, for tests and for hosts that opt out of Keychain persistence.
final class E2EEMemoryKeyStore: E2EEKeyStore {
    private var values: [String: Data] = [:]

    init() {}

    func get<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        guard let data = values[key] else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func set<T: Encodable>(_ key: String, _ value: T) {
        values[key] = try? JSONEncoder().encode(value)
    }

    func delete(_ key: String) {
        values.removeValue(forKey: key)
    }
}

/// Keychain-backed store, one generic-password item per key and account.
final class E2EEKeychainStore: E2EEKeyStore {
    private let service: String
    private let account: String

    /// - Parameter jid: the account's bare JID; each account gets its own items.
    init(jid: String) {
        self.service = "com.ethora.sdk.omemo"
        self.account = jid.lowercased()
    }

    private func query(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(account)|\(key)",
        ]
    }

    func get<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func set<T: Encodable>(_ key: String, _ value: T) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let match = query(key)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(match as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = match
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    func delete(_ key: String) {
        SecItemDelete(query(key) as CFDictionary)
    }
}
