//
//  E2EEOmemo.swift
//  XMPPChatCore
//
//  OMEMO 2 (XEP-0384 v0.8, urn:xmpp:omemo:2) for the SDK's MUC rooms. Translated from
//  ethora-chat-component/src/e2ee/omemo.ts. Every chat is a MUC room, so a message is
//  encrypted for the devices of EVERY member, and the author of an incoming stanza is
//  a room nick resolved to `<nick>@<domain>`. Only <body> is encrypted; the custom
//  <data> element rides beside <encrypted> in the clear because the server's push
//  pipeline has to read it.
//

import Foundation

/// Trust in a remote device. Blind trust before verification by default.
public enum E2EETrust: String, Codable, Equatable {
    case blind
    case verified
    case untrusted
    /// Sent from this device and read back from the local cache.
    case own
}

/// Result of decrypting one stanza.
struct E2EEDecrypted: Codable, Equatable {
    /// The SCE envelope content as XML. Nil for session-maintenance messages.
    var content: String?
    var trust: E2EETrust
    var error: String?
}

/// Device fingerprint info for UI.
public struct E2EEDeviceInfo: Equatable {
    public let id: UInt32
    public let fingerprint: String
    public let trust: E2EETrust
}

/// Errors raised by the OMEMO engine.
public enum E2EEOmemoError: Error, LocalizedError, Equatable {
    case noRecipients(String)
    case notReady
    case invalidHeader
    case invalidSenderDevice
    case unknownPrekey
    case noSession
    case unknownDevice
    case envelopeNotSCE
    case envelopeSenderMismatch
    case envelopeRecipientMismatch
    case noUsableBundle(String)

    public var errorDescription: String? {
        switch self {
        case .notReady: return "OMEMO is not ready yet"
        case .noRecipients(let members):
            return "omemo_no_recipients: no published OMEMO device for \(members) - they have to open the chat with encryption enabled at least once"
        case .invalidHeader: return "Invalid OMEMO header"
        case .invalidSenderDevice: return "Invalid OMEMO sender device"
        case .unknownPrekey: return "Unknown prekey"
        case .noSession: return "No session with the sender device"
        case .unknownDevice: return "Unknown device"
        case .envelopeNotSCE: return "Not an SCE envelope"
        case .envelopeSenderMismatch: return "Envelope sender mismatch"
        case .envelopeRecipientMismatch: return "Envelope recipient mismatch"
        case .noUsableBundle(let who): return "No usable bundle for \(who)"
        }
    }
}

/// Protocol constants shared by the OMEMO engine and the stanza seam.
public enum E2EEConstants {
    public static let nsOmemo = "urn:xmpp:omemo:2"
    /// Cleartext <body> of an encrypted stanza. Clients that cannot read OMEMO render it,
    /// and the server's push module copies it into the notification. Keep it neutral.
    public static let fallbackBody = "Encrypted message"
}

/// OMEMO 2 for one account on this device, across the MUC rooms it is in.
actor E2EEOmemo {

    // MARK: - Constants

    private static let nodeDevices = "urn:xmpp:omemo:2:devices"
    private static let nodeBundles = "urn:xmpp:omemo:2:bundles"
    private static let nsPubsub = "http://jabber.org/protocol/pubsub"
    private static let nsPubsubOwner = "http://jabber.org/protocol/pubsub#owner"
    private static let nsSce = "urn:xmpp:sce:1"
    private static let prekeyCount: UInt32 = 100
    private static let deviceListTTL: TimeInterval = 30

    // MARK: - Own keys

    struct OwnKeys: Codable {
        var deviceId: UInt32
        var identity: E2EEIdentityKey
        var spk: SignedPrekey
        /// Prekeys by id, keyed by the decimal id.
        var prekeys: [String: E2EEKeyPair]
        var nextPrekeyId: UInt32
    }

    struct SignedPrekey: Codable {
        var id: UInt32
        var pair: E2EEKeyPair
        var signature: Data
    }

    struct DeviceRecord: Codable {
        var ik: Data
        var trust: E2EETrust
    }

    // MARK: - State

    /// Our own bare JID, lowercased.
    nonisolated let jid: String
    private let transport: E2EETransport
    private let store: E2EEKeyStore
    private var keys: OwnKeys
    private var queueTail: Task<Void, Never>?
    private var deviceLists: [String: (ids: [UInt32], at: Date)] = [:]

    private init(transport: E2EETransport, jid: String, store: E2EEKeyStore, keys: OwnKeys) {
        self.transport = transport
        self.jid = E2EEOmemo.bare(jid)
        self.store = store
        self.keys = keys
    }

    /// Loads (or creates) this device's keys and publishes them. Safe on every login:
    /// the bundle is republished so prekeys stay fresh.
    static func create(transport: E2EETransport, jid: String, store: E2EEKeyStore) async throws -> E2EEOmemo {
        let keys: OwnKeys
        if let saved = store.get("keys", as: OwnKeys.self) {
            keys = saved
        } else {
            keys = generateOwnKeys()
            store.set("keys", keys)
        }
        let omemo = E2EEOmemo(transport: transport, jid: jid, store: store, keys: keys)
        try await omemo.publishBundle()
        try await omemo.announceDevice()
        return omemo
    }

    var deviceId: UInt32 { keys.deviceId }

    /// Identity key fingerprint, hex in groups of 8.
    var fingerprint: String { E2EEOmemo.formatFingerprint(keys.identity.pub) }

    static func formatFingerprint(_ ik: Data) -> String {
        let hex = E2EECrypto.toHex(ik)
        var groups: [String] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let end = hex.index(index, offsetBy: 8, limitedBy: hex.endIndex) ?? hex.endIndex
            groups.append(String(hex[index..<end]))
            index = end
        }
        return groups.joined(separator: " ")
    }

    static func generateOwnKeys() -> OwnKeys {
        let identity = E2EECrypto.generateIdentity()
        let spkPair = E2EECrypto.generateKeyPair()
        let signature = (try? E2EECrypto.sign(identity: identity, message: spkPair.pub)) ?? Data()
        var prekeys: [String: E2EEKeyPair] = [:]
        for id in 1...prekeyCount {
            prekeys["\(id)"] = E2EECrypto.generateKeyPair()
        }
        return OwnKeys(
            deviceId: UInt32(E2EECrypto.randomInt(1, 0x7fffffff)),
            identity: identity,
            spk: SignedPrekey(id: 1, pair: spkPair, signature: signature),
            prekeys: prekeys,
            nextPrekeyId: prekeyCount + 1
        )
    }

    // MARK: - Serialization

    /// Runs tasks one at a time: sessions and keys are read-modify-write.
    private func serial<T>(_ task: @escaping () async throws -> T) async throws -> T {
        let previous = queueTail
        let run = Task<T, Error> {
            await previous?.value
            return try await task()
        }
        queueTail = Task { _ = try? await run.value }
        return try await run.value
    }

    // MARK: - PEP

    /// Publishes, and repairs the node if its configuration blocks us. Reconfiguring is
    /// tried first because it keeps the published items; deleting the node is the last
    /// resort.
    private func publishWithRecovery(_ node: String, itemId: String, payload: XMPPStanza, maxItems: String?) async throws {
        do {
            try await publish(node, itemId: itemId, payload: payload, maxItems: maxItems)
            return
        } catch let error as E2EEIQError where isPreconditionNotMet(error) {
            // fall through to reconfigure
        }

        do {
            try await configureNode(node, maxItems: maxItems)
            try await publish(node, itemId: itemId, payload: payload, maxItems: maxItems)
            return
        } catch let error as E2EEIQError where isPreconditionNotMet(error) {
            // fall through to recreate
        }

        try await deleteNode(node)
        try await publish(node, itemId: itemId, payload: payload, maxItems: maxItems)
    }

    private func isPreconditionNotMet(_ error: E2EEIQError) -> Bool {
        error.condition == "precondition-not-met" || error.condition == "conflict"
    }

    private func configureNode(_ node: String, maxItems: String?) async throws {
        var fields = [
            formField("FORM_TYPE", "http://jabber.org/protocol/pubsub#node_config", type: "hidden"),
            formField("pubsub#access_model", "open"),
            formField("pubsub#persist_items", "true"),
        ]
        if let maxItems { fields.append(formField("pubsub#max_items", maxItems)) }
        let iq = XMPPStanza(name: "iq", attributes: ["type": "set"], children: [
            XMPPStanza(name: "pubsub", attributes: ["xmlns": E2EEOmemo.nsPubsubOwner], children: [
                XMPPStanza(name: "configure", attributes: ["node": node], children: [
                    XMPPStanza(name: "x", attributes: ["xmlns": "jabber:x:data", "type": "submit"], children: fields),
                ]),
            ]),
        ])
        _ = try await transport.e2eeSendIQ(iq)
    }

    private func deleteNode(_ node: String) async throws {
        let iq = XMPPStanza(name: "iq", attributes: ["type": "set"], children: [
            XMPPStanza(name: "pubsub", attributes: ["xmlns": E2EEOmemo.nsPubsubOwner], children: [
                XMPPStanza(name: "delete", attributes: ["node": node]),
            ]),
        ])
        _ = try await transport.e2eeSendIQ(iq)
    }

    private func publish(_ node: String, itemId: String, payload: XMPPStanza, maxItems: String?) async throws {
        var fields = [
            formField("FORM_TYPE", "http://jabber.org/protocol/pubsub#publish-options", type: "hidden"),
            formField("pubsub#access_model", "open"),
        ]
        if let maxItems { fields.append(formField("pubsub#max_items", maxItems)) }
        let iq = XMPPStanza(name: "iq", attributes: ["type": "set"], children: [
            XMPPStanza(name: "pubsub", attributes: ["xmlns": E2EEOmemo.nsPubsub], children: [
                XMPPStanza(name: "publish", attributes: ["node": node], children: [
                    XMPPStanza(name: "item", attributes: ["id": itemId], children: [payload]),
                ]),
                XMPPStanza(name: "publish-options", children: [
                    XMPPStanza(name: "x", attributes: ["xmlns": "jabber:x:data", "type": "submit"], children: fields),
                ]),
            ]),
        ])
        _ = try await transport.e2eeSendIQ(iq)
    }

    private func formField(_ name: String, _ value: String, type: String? = nil) -> XMPPStanza {
        var attributes = ["var": name]
        if let type { attributes["type"] = type }
        return XMPPStanza(name: "field", attributes: attributes, children: [
            XMPPStanza(name: "value", text: value),
        ])
    }

    /// Items of a PEP node on `jid`. An absent node is an empty list, not an error.
    private func fetchItems(_ jid: String, node: String, itemId: String? = nil) async throws -> [XMPPStanza] {
        var itemsChildren: [XMPPStanza] = []
        if let itemId {
            itemsChildren.append(XMPPStanza(name: "item", attributes: ["id": itemId]))
        }
        let iq = XMPPStanza(name: "iq", attributes: ["type": "get", "to": jid], children: [
            XMPPStanza(name: "pubsub", attributes: ["xmlns": E2EEOmemo.nsPubsub], children: [
                XMPPStanza(name: "items", attributes: ["node": node], children: itemsChildren),
            ]),
        ])
        do {
            let response = try await transport.e2eeSendIQ(iq)
            guard let pubsub = response.child("pubsub"), let items = pubsub.child("items") else { return [] }
            return items.children(named: "item")
        } catch let error as E2EEIQError where error.condition == "item-not-found" {
            return []
        }
    }

    private func fetchDeviceList(_ jid: String) async throws -> [XMPPStanza] {
        let items = try await fetchItems(jid, node: E2EEOmemo.nodeDevices)
        let list = items.first(where: { $0.attributes["id"] == "current" }) ?? items.first
        let devices = list?.child("devices", xmlns: E2EEConstants.nsOmemo)?.children(named: "device") ?? []
        return devices.filter { device in
            guard let id = UInt32(device.attributes["id"] ?? ""), id > 0 else { return false }
            return true
        }
    }

    private func deviceIds(_ jid: String, fresh: Bool = false) async throws -> [UInt32] {
        let target = E2EEOmemo.bare(jid)
        if !fresh, let cached = deviceLists[target], Date().timeIntervalSince(cached.at) < E2EEOmemo.deviceListTTL {
            return cached.ids
        }
        let ids = try await fetchDeviceList(target).compactMap { UInt32($0.attributes["id"] ?? "") }
        deviceLists[target] = (ids, Date())
        return ids
    }

    /// Adds this device to our published device list.
    private func announceDevice() async throws {
        let devices = try await fetchDeviceList(jid)
        if devices.contains(where: { UInt32($0.attributes["id"] ?? "") == deviceId }) { return }
        var children: [XMPPStanza] = devices.map { device in
            var attributes = ["id": device.attributes["id"] ?? ""]
            if let label = device.attributes["label"] { attributes["label"] = label }
            return XMPPStanza(name: "device", attributes: attributes)
        }
        children.append(XMPPStanza(name: "device", attributes: ["id": String(deviceId), "label": "iOS"]))
        let list = XMPPStanza(name: "devices", attributes: ["xmlns": E2EEConstants.nsOmemo], children: children)
        try await publishWithRecovery(E2EEOmemo.nodeDevices, itemId: "current", payload: list, maxItems: nil)
        deviceLists.removeValue(forKey: jid)
    }

    private func publishBundle() async throws {
        let bundle = XMPPStanza(name: "bundle", attributes: ["xmlns": E2EEConstants.nsOmemo], children: [
            XMPPStanza(name: "spk", attributes: ["id": String(keys.spk.id)], text: E2EEBase64.encode(keys.spk.pair.pub)),
            XMPPStanza(name: "spks", text: E2EEBase64.encode(keys.spk.signature)),
            XMPPStanza(name: "ik", text: E2EEBase64.encode(keys.identity.pub)),
            XMPPStanza(name: "prekeys", children: keys.prekeys
                .sorted { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }
                .map { entry in XMPPStanza(name: "pk", attributes: ["id": entry.key], text: E2EEBase64.encode(entry.value.pub)) }),
        ])
        try await publishWithRecovery(E2EEOmemo.nodeBundles, itemId: String(deviceId), payload: bundle, maxItems: "max")
    }

    private func fetchBundle(_ jid: String, id: UInt32) async throws -> E2EEBundle {
        let items = try await fetchItems(jid, node: E2EEOmemo.nodeBundles, itemId: String(id))
        let element = items.first(where: { $0.attributes["id"] == String(id) })?.child("bundle", xmlns: E2EEConstants.nsOmemo)
        let spk = element?.child("spk")
        let prekeys = element?.child("prekeys")?.children(named: "pk") ?? []
        guard let element, let spk, !prekeys.isEmpty, let pk = prekeys.randomElement() else {
            throw E2EEOmemoError.noUsableBundle("\(jid)/\(id)")
        }
        return E2EEBundle(
            ik: E2EEBase64.decode(element.childText("ik") ?? "") ?? Data(),
            spkId: UInt32(spk.attributes["id"] ?? "") ?? 0,
            spk: E2EEBase64.decode(spk.text ?? "") ?? Data(),
            spkSignature: E2EEBase64.decode(element.childText("spks") ?? "") ?? Data(),
            pkId: UInt32(pk.attributes["id"] ?? "") ?? 0,
            pk: E2EEBase64.decode(pk.text ?? "") ?? Data()
        )
    }

    // MARK: - Trust

    /// Records the device's identity key on first sight and returns its trust.
    private func trustOf(_ jid: String, id: UInt32, ik: Data) -> E2EETrust {
        var records = store.get(trustKey(jid), as: [String: DeviceRecord].self) ?? [:]
        if let known = records["\(id)"], E2EECrypto.bytesEqual(known.ik, ik) {
            return known.trust
        }
        // A new device, or a known device ID with a different key: never trusted blindly.
        let known = records["\(id)"] != nil
        let hasVerified = records.values.contains { $0.trust == .verified }
        let trust: E2EETrust = (known || hasVerified) ? .untrusted : .blind
        records["\(id)"] = DeviceRecord(ik: ik, trust: trust)
        store.set(trustKey(jid), records)
        return trust
    }

    /// Devices of `jid`, fetching unknown bundles. Includes this device for our own JID.
    func devices(of jid: String) async throws -> [E2EEDeviceInfo] {
        let target = E2EEOmemo.bare(jid)
        return try await serial {
            var result: [E2EEDeviceInfo] = []
            for id in try await self.deviceIds(target, fresh: true) {
                if target == self.jid && id == self.deviceId {
                    result.append(E2EEDeviceInfo(id: id, fingerprint: self.fingerprint, trust: .own))
                    continue
                }
                do {
                    let stored = self.store.get(self.trustKey(target), as: [String: DeviceRecord].self)?["\(id)"]
                    let ik: Data
                    if let stored {
                        ik = stored.ik
                    } else {
                        ik = try await self.fetchBundle(target, id: id).ik
                    }
                    let trust = self.trustOf(target, id: id, ik: ik)
                    result.append(E2EEDeviceInfo(id: id, fingerprint: E2EEOmemo.formatFingerprint(ik), trust: trust))
                } catch {
                    // A device without a usable bundle is skipped, like the web does.
                }
            }
            return result
        }
    }

    /// Sets the trust of a known device.
    func setTrust(_ jid: String, id: UInt32, trust: E2EETrust) async throws {
        let target = E2EEOmemo.bare(jid)
        try await serial {
            var records = self.store.get(self.trustKey(target), as: [String: DeviceRecord].self) ?? [:]
            guard var record = records["\(id)"] else { throw E2EEOmemoError.unknownDevice }
            record.trust = trust
            records["\(id)"] = record
            self.store.set(self.trustKey(target), records)
        }
    }

    // MARK: - Encryption

    /// Encrypts `keyMaterial` for every trusted device of `jid` (except this one).
    private func encryptKey(_ jid: String, keyMaterial: Data) async throws -> [XMPPStanza] {
        var out: [XMPPStanza] = []
        for id in try await deviceIds(jid) {
            if jid == self.jid && id == deviceId { continue }
            do {
                var session: E2EESession
                if let existing = store.get(sessionKey(jid, id), as: E2EESession.self) {
                    if trustOf(jid, id: id, ik: existing.peerIk) == .untrusted { continue }
                    session = existing
                } else {
                    let bundle = try await fetchBundle(jid, id: id)
                    if trustOf(jid, id: id, ik: bundle.ik) == .untrusted { continue }
                    session = try E2EERatchet.initiateSession(own: keys.identity, bundle: bundle)
                }

                let (next, data) = try E2EERatchet.ratchetEncrypt(session, plaintext: keyMaterial)
                store.set(sessionKey(jid, id), next)
                // Until the device answers, every message repeats the key exchange.
                var attributes = ["rid": String(id)]
                let encoded: Data
                if let kex = next.pendingKex {
                    encoded = E2EEProtobuf.encodeKeyExchange(E2EEKeyExchangeMessage(
                        pkId: kex.pkId,
                        spkId: kex.spkId,
                        ik: keys.identity.pub,
                        ek: kex.ek,
                        message: data
                    ))
                    attributes["kex"] = "true"
                } else {
                    encoded = data
                }
                out.append(XMPPStanza(name: "key", attributes: attributes, text: E2EEBase64.encode(encoded)))
            } catch {
                // A device we cannot reach is skipped, not fatal.
            }
        }
        return out
    }

    /// Builds the encrypted groupchat stanza for `roomJid`.
    ///
    /// - `content` goes inside the SCE envelope and is what OMEMO protects (today <body>).
    /// - `cleartext` is appended beside <encrypted>, untouched (the custom <data>).
    /// - `members` are the bare JIDs of everyone in the room; ours is added automatically.
    /// - `id` must be the id the plaintext stanza would have used.
    func encryptGroupMessage(
        roomJid: String,
        members: [String],
        content: [XMPPStanza],
        id: String,
        cleartext: [XMPPStanza] = []
    ) async throws -> XMPPStanza {
        try await serial {
            let room = E2EEOmemo.bare(roomJid)
            let recipients = E2EEOmemo.uniqueNonEmpty(members.map(E2EEOmemo.bare) + [self.jid])

            let envelope = XMPPStanza(name: "envelope", attributes: ["xmlns": E2EEOmemo.nsSce], children: [
                XMPPStanza(name: "content", children: content),
                XMPPStanza(name: "rpad", text: E2EEBase64.encode(E2EECrypto.randomBytes(E2EECrypto.randomInt(0, 48)))),
                XMPPStanza(name: "time", attributes: ["stamp": E2EEOmemo.isoTimestamp()]),
                XMPPStanza(name: "to", attributes: ["jid": room]),
                XMPPStanza(name: "from", attributes: ["jid": self.jid]),
            ])
            let (keyMaterial, payload) = try E2EERatchet.encryptPayload(Data(envelope.toXML().utf8))

            var blocks: [XMPPStanza] = []
            var unreachable: [String] = []
            for jid in recipients {
                var keyElements = try await self.encryptKey(jid, keyMaterial: keyMaterial)
                if keyElements.isEmpty && jid != self.jid {
                    // The member may have just added a device.
                    self.deviceLists.removeValue(forKey: jid)
                    keyElements = try await self.encryptKey(jid, keyMaterial: keyMaterial)
                }
                if !keyElements.isEmpty {
                    blocks.append(XMPPStanza(name: "keys", attributes: ["jid": jid], children: keyElements))
                } else if jid != self.jid {
                    unreachable.append(jid)
                }
            }
            if blocks.isEmpty {
                throw E2EEOmemoError.noRecipients(unreachable.isEmpty ? "any member" : unreachable.joined(separator: ", "))
            }

            // The room echoes our own message, but we never encrypt to this device, so keep
            // the plaintext under the id the echo will carry.
            let plaintext = content.map { $0.toXML() }.joined()
            self.store.set(self.messageKey(room, id: id), E2EEDecrypted(content: plaintext, trust: .own, error: nil))

            return XMPPStanza(
                name: "message",
                attributes: ["type": "groupchat", "to": room, "id": id],
                children: [
                    XMPPStanza(name: "encrypted", attributes: ["xmlns": E2EEConstants.nsOmemo], children: [
                        XMPPStanza(name: "header", attributes: ["sid": String(self.deviceId)], children: blocks),
                        XMPPStanza(name: "payload", text: E2EEBase64.encode(payload)),
                    ]),
                    XMPPStanza(name: "encryption", attributes: [
                        "xmlns": "urn:xmpp:eme:0",
                        "namespace": E2EEConstants.nsOmemo,
                        "name": "OMEMO",
                    ]),
                    XMPPStanza(name: "store", attributes: ["xmlns": "urn:xmpp:hints"]),
                    XMPPStanza(name: "origin-id", attributes: ["xmlns": "urn:xmpp:sid:0", "id": id]),
                    XMPPStanza(name: "body", text: E2EEConstants.fallbackBody),
                ] + cleartext
            )
        }
    }

    /// Empty OMEMO message: completes a session the peer started. It targets one device,
    /// so it goes straight to that member's real JID rather than through the room.
    private func sendEmpty(_ jid: String, id: UInt32) throws {
        guard let session = store.get(sessionKey(jid, id), as: E2EESession.self) else { return }
        let (next, data) = try E2EERatchet.ratchetEncrypt(session, plaintext: Data(count: 32))
        store.set(sessionKey(jid, id), next)
        let stanzaId = "omemo-empty-\(String(Int64(Date().timeIntervalSince1970 * 1000), radix: 36))"
        transport.e2eeSend(XMPPStanza(name: "message", attributes: ["type": "chat", "to": jid, "id": stanzaId], children: [
            XMPPStanza(name: "encrypted", attributes: ["xmlns": E2EEConstants.nsOmemo], children: [
                XMPPStanza(name: "header", attributes: ["sid": String(deviceId)], children: [
                    XMPPStanza(name: "keys", attributes: ["jid": jid], children: [
                        XMPPStanza(name: "key", attributes: ["rid": String(id)], text: E2EEBase64.encode(data)),
                    ]),
                ]),
            ]),
            XMPPStanza(name: "no-permanent-store", attributes: ["xmlns": "urn:xmpp:hints"]),
            XMPPStanza(name: "no-copy", attributes: ["xmlns": "urn:xmpp:hints"]),
            XMPPStanza(name: "private", attributes: ["xmlns": "urn:xmpp:carbons:2"]),
        ]))
    }

    // MARK: - Decryption

    /// Decrypts one OMEMO stanza. `sender` is the real bare JID of the author and
    /// `roomJid` the room it arrived in. Returns nil when the stanza has no <encrypted>.
    func decrypt(carrier: XMPPStanza, sender: String, roomJid: String) async throws -> E2EEDecrypted? {
        guard let encrypted = carrier.child("encrypted", xmlns: E2EEConstants.nsOmemo) else { return nil }
        let from = E2EEOmemo.bare(sender)
        let room = E2EEOmemo.bare(roomJid)
        return try await serial {
            let cacheId = carrier.attributes["id"].map { self.messageKey(room, id: $0) }
            if let cacheId, let cached = self.store.get(cacheId, as: E2EEDecrypted.self) {
                return cached
            }
            // Empty messages are not shown, so their failures do not matter either.
            let empty = encrypted.child("payload") == nil
            do {
                let result = try self.decryptUncached(encrypted, sender: from, roomJid: room)
                if empty { return E2EEDecrypted(content: nil, trust: result.trust, error: nil) }
                // Also makes repeated deliveries (live, mucsub, archive) idempotent.
                if let cacheId, result.error == nil {
                    self.store.set(cacheId, result)
                }
                return result
            } catch {
                if empty { return E2EEDecrypted(content: nil, trust: .untrusted, error: nil) }
                return E2EEDecrypted(content: nil, trust: .untrusted, error: "omemo_decrypt_failed")
            }
        }
    }

    private func decryptUncached(_ encrypted: XMPPStanza, sender: String, roomJid: String) throws -> E2EEDecrypted {
        guard let header = encrypted.child("header"),
              let sid = UInt32(header.attributes["sid"] ?? "") else {
            throw E2EEOmemoError.invalidHeader
        }
        if sender == self.jid && sid == deviceId {
            return E2EEDecrypted(content: nil, trust: .own, error: "omemo_own_message_not_cached")
        }

        let keyElement = header.children(named: "keys")
            .filter { E2EEOmemo.bare($0.attributes["jid"] ?? "") == self.jid }
            .flatMap { $0.children(named: "key") }
            .first { UInt32($0.attributes["rid"] ?? "") == deviceId }
        guard let keyElement else {
            return E2EEDecrypted(content: nil, trust: .untrusted, error: "omemo_not_encrypted_for_this_device")
        }

        let data = E2EEBase64.decode(keyElement.text ?? "") ?? Data()
        let existing = store.get(sessionKey(sender, sid), as: E2EESession.self)
        var session: E2EESession
        var keyMaterial: Data
        var usedPrekey: UInt32?

        let isKex = keyElement.attributes["kex"] == "true" || keyElement.attributes["kex"] == "1"
        if isKex {
            let kex = try E2EEProtobuf.decodeKeyExchange(data)
            if let existing, let existingEk = existing.kexEk,
               E2EECrypto.bytesEqual(existingEk, kex.ek), E2EECrypto.bytesEqual(existing.peerIk, kex.ik) {
                // Repeated key exchange of a session we already accepted.
                (session, keyMaterial) = try E2EERatchet.ratchetDecrypt(existing, data: kex.message)
            } else {
                guard kex.spkId == keys.spk.id, let pk = keys.prekeys["\(kex.pkId)"] else {
                    throw E2EEOmemoError.unknownPrekey
                }
                let accepted = try E2EERatchet.acceptSession(
                    own: keys.identity,
                    spk: keys.spk.pair,
                    pk: pk,
                    peerIk: kex.ik,
                    ek: kex.ek
                )
                (session, keyMaterial) = try E2EERatchet.ratchetDecrypt(accepted, data: kex.message)
                usedPrekey = kex.pkId
            }
        } else {
            guard let existing else { throw E2EEOmemoError.noSession }
            (session, keyMaterial) = try E2EERatchet.ratchetDecrypt(existing, data: data)
        }
        // The device answered: no need to repeat our key exchange.
        session.pendingKex = nil

        var content: String?
        if let payloadText = encrypted.childText("payload") {
            let payload = E2EEBase64.decode(payloadText) ?? Data()
            let plain = try E2EERatchet.decryptPayload(keyMaterial: keyMaterial, payload: payload)
            content = try openEnvelope(plain, sender: sender, roomJid: roomJid)
        }
        let trust = trustOf(sender, id: sid, ik: session.peerIk)
        store.set(sessionKey(sender, sid), session)

        if let usedPrekey {
            try replacePrekey(usedPrekey)
            // After this task: republish the bundle and confirm the new session.
            let owner = self
            Task {
                do {
                    try await owner.serial {
                        try await owner.publishBundle()
                        try await owner.sendEmptyFor(sender, id: sid)
                    }
                } catch {
                    print("[E2EE] failed to complete key exchange: \(error)")
                }
            }
        }
        return E2EEDecrypted(content: content, trust: trust, error: nil)
    }

    private func sendEmptyFor(_ jid: String, id: UInt32) throws {
        try sendEmpty(jid, id: id)
    }

    /// Checks the SCE envelope (XEP-0420) and returns its content as XML. The from/to check
    /// stops one member replaying another member's message under their own nick.
    private func openEnvelope(_ bytes: Data, sender: String, roomJid: String) throws -> String {
        guard let text = String(data: bytes, encoding: .utf8),
              let envelope = XMPPStanzaParser.parse(text),
              envelope.name == "envelope", envelope.attributes["xmlns"] == E2EEOmemo.nsSce else {
            throw E2EEOmemoError.envelopeNotSCE
        }
        guard let from = envelope.child("from")?.attributes["jid"], E2EEOmemo.bare(from) == sender else {
            throw E2EEOmemoError.envelopeSenderMismatch
        }
        guard let to = envelope.child("to")?.attributes["jid"], E2EEOmemo.bare(to) == roomJid else {
            throw E2EEOmemoError.envelopeRecipientMismatch
        }
        return (envelope.child("content")?.children ?? []).map { $0.toXML() }.joined()
    }

    private func replacePrekey(_ id: UInt32) throws {
        var updated = keys
        updated.prekeys.removeValue(forKey: "\(id)")
        updated.prekeys["\(updated.nextPrekeyId)"] = E2EECrypto.generateKeyPair()
        updated.nextPrekeyId += 1
        store.set("keys", updated)
        keys = updated
    }

    // MARK: - Keys

    private func sessionKey(_ jid: String, _ id: UInt32) -> String { "session:\(E2EEOmemo.bare(jid)):\(id)" }
    private func trustKey(_ jid: String) -> String { "trust:\(E2EEOmemo.bare(jid))" }
    /// Keyed by room, since a MUC message id is unique within its room.
    private func messageKey(_ roomJid: String, id: String) -> String { "message:\(E2EEOmemo.bare(roomJid)):\(id)" }

    // MARK: - Helpers

    static func bare(_ jid: String) -> String {
        String(jid.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first ?? "").lowercased()
    }

    private static func uniqueNonEmpty(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for value in values where !value.isEmpty && !seen.contains(value) {
            seen.insert(value)
            out.append(value)
        }
        return out
    }

    private static func isoTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date())
    }
}

// MARK: - XML helpers

extension XMPPStanza {
    /// First child with this name, and, when the child carries an xmlns attribute, that namespace.
    func child(_ name: String, xmlns: String? = nil) -> XMPPStanza? {
        children.first { candidate in
            guard candidate.name == name else { return false }
            guard let xmlns else { return true }
            return candidate.attributes["xmlns"] == nil || candidate.attributes["xmlns"] == xmlns
        }
    }

    func children(named name: String) -> [XMPPStanza] {
        children.filter { $0.name == name }
    }

    func childText(_ name: String) -> String? {
        child(name)?.text
    }
}
