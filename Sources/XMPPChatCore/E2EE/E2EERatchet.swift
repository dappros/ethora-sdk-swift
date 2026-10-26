//
//  E2EERatchet.swift
//  XMPPChatCore
//
//  X3DH and Double Ratchet as profiled by OMEMO 2 (XEP-0384 sections 6-7), plus the
//  SCE payload encryption. Byte-compatible with ethora-chat-component/src/e2ee/ratchet.ts.
//  Key generators are parameters so known-answer vectors can pin every byte.
//

import Foundation

enum E2EERatchetError: Error, LocalizedError, Equatable {
    case cannotSendYet
    case messageWithoutCiphertext
    case authenticationFailed
    case payloadAuthenticationFailed
    case invalidKeyMaterial
    case tooManySkippedMessages

    var errorDescription: String? {
        switch self {
        case .cannotSendYet: return "Session cannot send yet"
        case .messageWithoutCiphertext: return "Message without ciphertext"
        case .authenticationFailed: return "Message authentication failed"
        case .payloadAuthenticationFailed: return "Payload authentication failed"
        case .invalidKeyMaterial: return "Invalid key material"
        case .tooManySkippedMessages: return "Too many skipped messages"
        }
    }
}

/// A published bundle of a remote device (PEP `urn:xmpp:omemo:2:bundles`).
struct E2EEBundle: Equatable {
    var ik: Data
    var spkId: UInt32
    var spk: Data
    var spkSignature: Data
    var pkId: UInt32
    var pk: Data
}

/// Message keys of skipped messages, keyed by "<base64 dhPub>:<n>".
struct E2EESkippedKey: Codable, Equatable {
    var id: String
    var mk: Data
}

/// We initiated and have had no reply yet: outgoing messages carry a key exchange.
struct E2EEPendingKex: Codable, Equatable {
    var pkId: UInt32
    var spkId: UInt32
    var ek: Data
}

/// Ratchet state for one peer device. Plain value data, so it can be stored as JSON.
struct E2EESession: Codable, Equatable {
    var rk: Data
    var dhs: E2EEKeyPair
    var dhr: Data?
    var cks: Data?
    var ckr: Data?
    var ns: Int
    var nr: Int
    var pn: Int
    /// Skipped message keys, oldest first (trimmed from the front past the limit).
    var skipped: [E2EESkippedKey]
    /// X3DH associated data: initiator IK || responder IK.
    var ad: Data
    /// The peer device's Ed25519 identity key.
    var peerIk: Data
    var pendingKex: E2EEPendingKex?
    /// Ephemeral key of the key exchange that created this session (responder side).
    var kexEk: Data?
}

enum E2EERatchet {

    /// Max message keys skipped in one chain, and kept in total.
    static let maxSkip = 1000
    private static let x3dhPrefix = Data(repeating: 0xff, count: 32)

    // MARK: - KDFs

    /// Root-chain KDF. Returns (new root key, new chain key).
    static func kdfRk(_ rk: Data, _ dhOut: Data) -> (Data, Data) {
        let out = E2EECrypto.hkdfSha256(ikm: dhOut, salt: rk, info: "OMEMO Root Chain", length: 64)
        return (Data(out.prefix(32)), Data(out.suffix(32)))
    }

    /// Chain KDF. Returns (next chain key, message key).
    static func kdfCk(_ ck: Data) -> (Data, Data) {
        (
            E2EECrypto.hmacSha256(key: ck, data: Data([0x02])),
            E2EECrypto.hmacSha256(key: ck, data: Data([0x01]))
        )
    }

    struct MessageKeys {
        let enc: Data
        let auth: Data
        let iv: Data
    }

    static func messageKeys(_ mk: Data) -> MessageKeys {
        let km = E2EECrypto.hkdfSha256(ikm: mk, salt: nil, info: "OMEMO Message Key Material", length: 80)
        return MessageKeys(enc: Data(km.prefix(32)), auth: Data(km[32..<64]), iv: Data(km.suffix(16)))
    }

    private static func x3dhSecret(_ dhs: [Data]) -> Data {
        E2EECrypto.hkdfSha256(
            ikm: x3dhPrefix + dhs.reduce(Data(), +),
            salt: nil,
            info: "OMEMO X3DH",
            length: 32
        )
    }

    // MARK: - X3DH

    /// Starts a session with a device from its bundle (X3DH, active side).
    static func initiateSession(
        own: E2EEIdentityKey,
        bundle: E2EEBundle,
        ek: E2EEKeyPair = E2EECrypto.generateKeyPair(),
        dhs: E2EEKeyPair = E2EECrypto.generateKeyPair()
    ) throws -> E2EESession {
        guard E2EECrypto.verify(signature: bundle.spkSignature, message: bundle.spk, identityPub: bundle.ik) else {
            throw E2EECryptoError.invalidSignature
        }
        guard let peerDh = E2EECrypto.identityDhPublic(identityPub: bundle.ik) else {
            throw E2EECryptoError.lowOrderPoint
        }
        let ownDh = E2EECrypto.identityDhPrivate(seed: own.seed)
        let sk = x3dhSecret([
            try E2EECrypto.dh(priv: ownDh, pub: bundle.spk),
            try E2EECrypto.dh(priv: ek.priv, pub: peerDh),
            try E2EECrypto.dh(priv: ek.priv, pub: bundle.spk),
            try E2EECrypto.dh(priv: ek.priv, pub: bundle.pk),
        ])
        let (rk, cks) = kdfRk(sk, try E2EECrypto.dh(priv: dhs.priv, pub: bundle.spk))
        return E2EESession(
            rk: rk,
            dhs: dhs,
            dhr: bundle.spk,
            cks: cks,
            ckr: nil,
            ns: 0,
            nr: 0,
            pn: 0,
            skipped: [],
            ad: own.pub + bundle.ik,
            peerIk: bundle.ik,
            pendingKex: E2EEPendingKex(pkId: bundle.pkId, spkId: bundle.spkId, ek: ek.pub),
            kexEk: nil
        )
    }

    /// Builds the session from a received key exchange (X3DH, passive side).
    static func acceptSession(
        own: E2EEIdentityKey,
        spk: E2EEKeyPair,
        pk: E2EEKeyPair,
        peerIk: Data,
        ek: Data
    ) throws -> E2EESession {
        guard let peerDh = E2EECrypto.identityDhPublic(identityPub: peerIk) else {
            throw E2EECryptoError.lowOrderPoint
        }
        let sk = x3dhSecret([
            try E2EECrypto.dh(priv: spk.priv, pub: peerDh),
            try E2EECrypto.dh(priv: E2EECrypto.identityDhPrivate(seed: own.seed), pub: ek),
            try E2EECrypto.dh(priv: spk.priv, pub: ek),
            try E2EECrypto.dh(priv: pk.priv, pub: ek),
        ])
        return E2EESession(
            rk: sk,
            dhs: spk,
            dhr: nil,
            cks: nil,
            ckr: nil,
            ns: 0,
            nr: 0,
            pn: 0,
            skipped: [],
            ad: peerIk + own.pub,
            peerIk: peerIk,
            pendingKex: nil,
            kexEk: ek
        )
    }

    // MARK: - Encrypt / decrypt

    /// Encrypts with the sending chain. Returns the new state and an encoded
    /// OMEMOAuthenticatedMessage.
    static func ratchetEncrypt(_ session: E2EESession, plaintext: Data) throws -> (E2EESession, Data) {
        guard let cks = session.cks else { throw E2EERatchetError.cannotSendYet }
        var s = session
        let (nextCk, mk) = kdfCk(cks)
        s.cks = nextCk

        let keys = messageKeys(mk)
        let ciphertext = try E2EECrypto.aesEncrypt(key: keys.enc, iv: keys.iv, data: plaintext)
        let message = E2EEProtobuf.encodeMessage(E2EEOmemoMessage(
            n: UInt32(s.ns),
            pn: UInt32(s.pn),
            dhPub: s.dhs.pub,
            ciphertext: ciphertext
        ))
        s.ns += 1
        let mac = Data(E2EECrypto.hmacSha256(key: keys.auth, data: s.ad + message).prefix(16))
        return (s, E2EEProtobuf.encodeAuthenticated(E2EEAuthenticatedMessage(mac: mac, message: message)))
    }

    /// Decrypts an encoded OMEMOAuthenticatedMessage. The input session is left
    /// untouched; the returned one must be stored only after the whole message
    /// was processed successfully.
    static func ratchetDecrypt(
        _ session: E2EESession,
        data: Data,
        keyGenerator: () -> E2EEKeyPair = E2EECrypto.generateKeyPair
    ) throws -> (E2EESession, Data) {
        let authenticated = try E2EEProtobuf.decodeAuthenticated(data)
        let header = try E2EEProtobuf.decodeMessage(authenticated.message)
        guard let ciphertext = header.ciphertext else { throw E2EERatchetError.messageWithoutCiphertext }
        var s = session
        let ad = session.ad
        let mac = authenticated.mac
        let message = authenticated.message

        func decrypt(_ mk: Data) throws -> Data {
            let keys = messageKeys(mk)
            let expected = Data(E2EECrypto.hmacSha256(key: keys.auth, data: ad + message).prefix(16))
            guard E2EECrypto.bytesEqual(expected, mac) else { throw E2EERatchetError.authenticationFailed }
            return try E2EECrypto.aesDecrypt(key: keys.enc, iv: keys.iv, data: ciphertext)
        }

        let skippedId = "\(E2EEBase64.encode(header.dhPub)):\(header.n)"
        if let index = s.skipped.firstIndex(where: { $0.id == skippedId }) {
            let mk = s.skipped.remove(at: index).mk
            return (s, try decrypt(mk))
        }

        if s.dhr == nil || !E2EECrypto.bytesEqual(header.dhPub, s.dhr!) {
            try skipMessageKeys(&s, until: Int(header.pn))
            s.pn = s.ns
            s.ns = 0
            s.nr = 0
            s.dhr = header.dhPub
            let (rkA, ckr) = kdfRk(s.rk, try E2EECrypto.dh(priv: s.dhs.priv, pub: s.dhr!))
            s.rk = rkA
            s.ckr = ckr
            s.dhs = keyGenerator()
            let (rkB, cks) = kdfRk(s.rk, try E2EECrypto.dh(priv: s.dhs.priv, pub: s.dhr!))
            s.rk = rkB
            s.cks = cks
        }

        try skipMessageKeys(&s, until: Int(header.n))
        guard let ckr = s.ckr else { throw E2EERatchetError.cannotSendYet }
        let (nextCkr, mk) = kdfCk(ckr)
        s.ckr = nextCkr
        s.nr += 1
        return (s, try decrypt(mk))
    }

    private static func skipMessageKeys(_ s: inout E2EESession, until: Int) throws {
        guard var ckr = s.ckr, let dhr = s.dhr else { return }
        if until - s.nr > maxSkip { throw E2EERatchetError.tooManySkippedMessages }
        let dhrId = E2EEBase64.encode(dhr)
        while s.nr < until {
            let (next, mk) = kdfCk(ckr)
            ckr = next
            let id = "\(dhrId):\(s.nr)"
            if let existing = s.skipped.firstIndex(where: { $0.id == id }) {
                s.skipped[existing].mk = mk
            } else {
                s.skipped.append(E2EESkippedKey(id: id, mk: mk))
            }
            s.nr += 1
        }
        s.ckr = ckr
        let overflow = s.skipped.count - maxSkip
        if overflow > 0 {
            s.skipped.removeFirst(overflow)
        }
    }

    // MARK: - Payload (XEP-0384 section 4.4)

    private static func payloadKeys(_ key: Data) -> MessageKeys {
        let km = E2EECrypto.hkdfSha256(ikm: key, salt: nil, info: "OMEMO Payload", length: 80)
        return MessageKeys(enc: Data(km.prefix(32)), auth: Data(km[32..<64]), iv: Data(km.suffix(16)))
    }

    /// Encrypts the SCE envelope. `keyMaterial` (key || truncated HMAC, 48 bytes)
    /// is what gets encrypted for every recipient device.
    static func encryptPayload(_ plaintext: Data, key: Data = E2EECrypto.randomBytes(32)) throws -> (keyMaterial: Data, payload: Data) {
        let keys = payloadKeys(key)
        let payload = try E2EECrypto.aesEncrypt(key: keys.enc, iv: keys.iv, data: plaintext)
        let mac = Data(E2EECrypto.hmacSha256(key: keys.auth, data: payload).prefix(16))
        return (key + mac, payload)
    }

    static func decryptPayload(keyMaterial: Data, payload: Data) throws -> Data {
        guard keyMaterial.count == 48 else { throw E2EERatchetError.invalidKeyMaterial }
        let keys = payloadKeys(Data(keyMaterial.prefix(32)))
        let expected = Data(E2EECrypto.hmacSha256(key: keys.auth, data: payload).prefix(16))
        guard E2EECrypto.bytesEqual(expected, Data(keyMaterial.suffix(16))) else {
            throw E2EERatchetError.payloadAuthenticationFailed
        }
        return try E2EECrypto.aesDecrypt(key: keys.enc, iv: keys.iv, data: payload)
    }
}
