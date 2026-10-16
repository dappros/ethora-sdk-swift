//
//  E2EECrypto.swift
//  XMPPChatCore
//
//  Platform-crypto primitives for OMEMO 2 (XEP-0384 v0.8) end-to-end encryption.
//  Byte-compatible with ethora-chat-component/src/e2ee/crypto.ts.
//  HKDF-SHA256, HMAC-SHA256, X25519 and Ed25519 come from CryptoKit; AES-256-CBC
//  (PKCS#7) comes from CommonCrypto. Only the Ed25519 -> X25519 public-key map
//  is arithmetic of our own (see E2EEEdwards.swift), and it is pinned by vectors.
//

import Foundation
import CryptoKit
import CommonCrypto

/// An X25519 key pair (raw 32-byte scalars and u-coordinates).
public struct E2EEKeyPair: Codable, Equatable {
    public var priv: Data
    public var pub: Data

    public init(priv: Data, pub: Data) {
        self.priv = priv
        self.pub = pub
    }
}

/// Ed25519 identity key: `seed` is the 32-byte Ed25519 secret, `pub` the public key.
public struct E2EEIdentityKey: Codable, Equatable {
    public var seed: Data
    public var pub: Data

    public init(seed: Data, pub: Data) {
        self.seed = seed
        self.pub = pub
    }
}

public enum E2EECryptoError: Error, LocalizedError, Equatable {
    case aesFailed(Int32)
    case invalidKey(String)
    case invalidSignature
    case lowOrderPoint

    public var errorDescription: String? {
        switch self {
        case .aesFailed(let status): return "AES-CBC failed with status \(status)"
        case .invalidKey(let what): return "Invalid key material: \(what)"
        case .invalidSignature: return "Invalid signed prekey signature"
        case .lowOrderPoint: return "Diffie-Hellman produced an unusable shared secret"
        }
    }
}

/// Thin wrappers over the platform primitives, using the same names and
/// conventions as crypto.ts so the ratchet code reads like the web source.
enum E2EECrypto {

    // MARK: - KDF / MAC

    /// HKDF-SHA256. A nil salt means 32 zero bytes, exactly as in crypto.ts.
    static func hkdfSha256(ikm: Data, salt: Data?, info: String, length: Int) -> Data {
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ikm),
            salt: salt ?? Data(count: 32),
            info: Data(info.utf8),
            outputByteCount: length
        )
        return derived.withUnsafeBytes { Data($0) }
    }

    static func hmacSha256(key: Data, data: Data) -> Data {
        let code = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))
        return Data(code)
    }

    // MARK: - AES-256-CBC with PKCS#7

    static func aesEncrypt(key: Data, iv: Data, data: Data) throws -> Data {
        try aesCrypt(operation: CCOperation(kCCEncrypt), key: key, iv: iv, data: data)
    }

    static func aesDecrypt(key: Data, iv: Data, data: Data) throws -> Data {
        try aesCrypt(operation: CCOperation(kCCDecrypt), key: key, iv: iv, data: data)
    }

    private static func aesCrypt(operation: CCOperation, key: Data, iv: Data, data: Data) throws -> Data {
        guard key.count == kCCKeySizeAES256 else { throw E2EECryptoError.invalidKey("aes key length \(key.count)") }
        guard iv.count == kCCBlockSizeAES128 else { throw E2EECryptoError.invalidKey("aes iv length \(iv.count)") }
        var out = Data(count: data.count + kCCBlockSizeAES128)
        var moved = 0
        let status: CCCryptorStatus = out.withUnsafeMutableBytes { outPtr in
            data.withUnsafeBytes { inPtr in
                key.withUnsafeBytes { keyPtr in
                    iv.withUnsafeBytes { ivPtr in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress, key.count,
                            ivPtr.baseAddress,
                            inPtr.baseAddress, data.count,
                            outPtr.baseAddress, outPtr.count,
                            &moved
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw E2EECryptoError.aesFailed(status) }
        return out.prefix(moved)
    }

    // MARK: - X25519

    static func generateKeyPair() -> E2EEKeyPair {
        let key = Curve25519.KeyAgreement.PrivateKey()
        return E2EEKeyPair(priv: key.rawRepresentation, pub: key.publicKey.rawRepresentation)
    }

    /// The X25519 public key for a 32-byte private scalar (clamped by CryptoKit).
    static func x25519PublicKey(priv: Data) throws -> Data {
        let key = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: priv)
        return key.publicKey.rawRepresentation
    }

    /// X25519 shared secret. Throws on low-order public keys.
    static func dh(priv: Data, pub: Data) throws -> Data {
        do {
            let sk = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: priv)
            let pk = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: pub)
            let secret = try sk.sharedSecretFromKeyAgreement(with: pk)
            return secret.withUnsafeBytes { Data($0) }
        } catch {
            throw E2EECryptoError.lowOrderPoint
        }
    }

    // MARK: - Ed25519

    static func generateIdentity() -> E2EEIdentityKey {
        let key = Curve25519.Signing.PrivateKey()
        return E2EEIdentityKey(seed: key.rawRepresentation, pub: key.publicKey.rawRepresentation)
    }

    static func identityPublicKey(seed: Data) throws -> Data {
        try Curve25519.Signing.PrivateKey(rawRepresentation: seed).publicKey.rawRepresentation
    }

    static func sign(identity: E2EEIdentityKey, message: Data) throws -> Data {
        try Curve25519.Signing.PrivateKey(rawRepresentation: identity.seed).signature(for: message)
    }

    static func verify(signature: Data, message: Data, identityPub: Data) -> Bool {
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: identityPub) else { return false }
        return key.isValidSignature(signature, for: message)
    }

    /// The X25519 private scalar of an Ed25519 identity: SHA-512(seed)[0..<32], clamped.
    /// Matches edwardsToMontgomeryPriv in noble-curves.
    static func identityDhPrivate(seed: Data) -> Data {
        var scalar = Data(SHA512.hash(data: seed).prefix(32))
        scalar[0] &= 248
        scalar[31] &= 127
        scalar[31] |= 64
        return scalar
    }

    /// The X25519 public key of an Ed25519 identity (birational map), or nil for a
    /// point that has no Montgomery form.
    static func identityDhPublic(identityPub: Data) -> Data? {
        E2EEEdwards.montgomeryU(edwardsPublicKey: identityPub)
    }

    // MARK: - Misc

    /// Constant-time comparison.
    static func bytesEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for (x, y) in zip(a, b) { diff |= x ^ y }
        return diff == 0
    }

    static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return Data(bytes)
    }

    /// Random integer in [min, max].
    static func randomInt(_ min: Int, _ max: Int) -> Int {
        let span = UInt64(max - min + 1)
        var value: UInt64 = 0
        let bytes = randomBytes(8)
        for byte in bytes { value = (value << 8) | UInt64(byte) }
        return min + Int(value % span)
    }

    static func toHex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

/// Base64 helpers using the standard alphabet with padding, like btoa/atob.
enum E2EEBase64 {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
    }

    static func decode(_ text: String) -> Data? {
        let cleaned = text.filter { !$0.isWhitespace }
        return Data(base64Encoded: cleaned)
    }
}
