//
//  E2EEFileEnvelope.swift
//  XMPPChatCore
//
//  Attachment sealing for end-to-end encrypted rooms. Byte-compatible with
//  ethora-chat-component/src/e2ee/fileEnvelope.ts.
//
//  The file is sealed before upload: the server stores opaque bytes under a random
//  name with the clientEncrypted form flag, and the real mimetype and filename travel
//  inside the sealed payload. The 48-byte key material belongs to the message and
//  rides in the OMEMO-encrypted <body>.
//
//  Envelope layout: MAGIC(8) | version(1) | headerLen(4, big-endian) | headerJSON | fileBytes
//

import Foundation

enum E2EEFileEnvelopeError: Error, LocalizedError, Equatable {
    case truncated
    case badMagic
    case unsupportedVersion(UInt8)
    case invalidHeader

    var errorDescription: String? {
        switch self {
        case .truncated: return "file_envelope_truncated"
        case .badMagic: return "file_envelope_bad_magic"
        case .unsupportedVersion(let version): return "file_envelope_unsupported_version_\(version)"
        case .invalidHeader: return "file_envelope_invalid_header"
        }
    }
}

/// What the server must not learn, and the receiver needs to render.
struct E2EEFileMeta: Equatable {
    var mimetype: String
    var originalname: String
    var size: Int
}

/// A sealed file, ready to upload.
struct E2EESealedFile: Equatable {
    /// Ciphertext, ready to upload.
    var ciphertext: Data
    /// Base64 of the 48-byte key material. Belongs in the encrypted <body>.
    var keyMaterial: String
    /// Random, extension-free name to upload under.
    var filename: String
}

/// The keys and caption of a sealed media <body>.
struct E2EESealedMediaPayload: Equatable {
    var keys: [String]
    var caption: String?
    var captionMentions: [E2EEMentionSpan]?
}

/// An @-mention span inside a caption, mirroring IMentionSpan on the web.
struct E2EEMentionSpan: Codable, Equatable {
    var jid: String
    var name: String
    var offset: Int
    var length: Int
}

enum E2EEFileEnvelope {

    static let magic: [UInt8] = Array("ETHOFILE".utf8)
    static let version: UInt8 = 1
    private static let headerOffset = 8 + 1 + 4

    /// MAGIC | version | headerLen (big-endian) | headerJSON | fileBytes.
    /// The header JSON keeps web key order (mimetype, originalname, size) so the
    /// bytes match what JSON.stringify produces for the same metadata.
    static func encode(meta: E2EEFileMeta, bytes: Data) -> Data {
        let header = Data(headerJSON(meta).utf8)
        var out = Data(magic)
        out.append(version)
        let length = UInt32(header.count)
        out.append(contentsOf: [UInt8(length >> 24), UInt8((length >> 16) & 0xff), UInt8((length >> 8) & 0xff), UInt8(length & 0xff)])
        out.append(header)
        out.append(bytes)
        return out
    }

    static func decode(_ envelope: Data) throws -> (meta: E2EEFileMeta, bytes: Data) {
        guard envelope.count >= headerOffset else { throw E2EEFileEnvelopeError.truncated }
        let bytes = [UInt8](envelope)
        for index in 0..<magic.count where bytes[index] != magic[index] {
            throw E2EEFileEnvelopeError.badMagic
        }
        let found = bytes[magic.count]
        guard found == version else { throw E2EEFileEnvelopeError.unsupportedVersion(found) }
        let headerLen = (Int(bytes[9]) << 24) | (Int(bytes[10]) << 16) | (Int(bytes[11]) << 8) | Int(bytes[12])
        let bodyStart = headerOffset + headerLen
        guard bodyStart <= bytes.count else { throw E2EEFileEnvelopeError.truncated }
        let headerData = Data(bytes[headerOffset..<bodyStart])
        guard let object = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              let mimetype = object["mimetype"] as? String,
              let originalname = object["originalname"] as? String,
              let size = object["size"] as? Int else {
            throw E2EEFileEnvelopeError.invalidHeader
        }
        return (E2EEFileMeta(mimetype: mimetype, originalname: originalname, size: size), Data(bytes[bodyStart...]))
    }

    /// Seals a file for upload. A fresh random key is used per call.
    static func sealForUpload(
        bytes: Data,
        mimetype: String?,
        originalName: String?,
        key: Data = E2EECrypto.randomBytes(32),
        filenameBytes: Data = E2EECrypto.randomBytes(16)
    ) throws -> E2EESealedFile {
        let meta = E2EEFileMeta(
            mimetype: (mimetype?.isEmpty == false) ? mimetype! : "application/octet-stream",
            originalname: (originalName?.isEmpty == false) ? originalName! : "blob",
            size: bytes.count
        )
        let envelope = encode(meta: meta, bytes: bytes)
        let sealed = try E2EERatchet.encryptPayload(envelope, key: key)
        return E2EESealedFile(
            ciphertext: sealed.payload,
            keyMaterial: E2EEBase64.encode(sealed.keyMaterial),
            filename: E2EECrypto.toHex(filenameBytes)
        )
    }

    /// Inverse of sealForUpload, for the receiving side.
    static func open(ciphertext: Data, keyMaterial: String) throws -> (meta: E2EEFileMeta, bytes: Data) {
        guard let key = E2EEBase64.decode(keyMaterial) else { throw E2EERatchetError.invalidKeyMaterial }
        let plain = try E2EERatchet.decryptPayload(keyMaterial: key, payload: ciphertext)
        return try decode(plain)
    }

    /// Reads the attachment keys (and caption) out of a decrypted media <body>:
    /// `{"v":1,"keys":[...],"caption"?,"captionMentions"?}`. Returns nil for anything
    /// else, so an ordinary media message falls through untouched.
    static func parseSealedMediaPayload(_ body: String?) -> E2EESealedMediaPayload? {
        let text = (body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("{"), let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        // `v` must be the number 1 (not the boolean true, which JSON bridges to NSNumber too).
        guard let versionValue = object["v"] as? NSNumber,
              CFGetTypeID(versionValue) != CFBooleanGetTypeID(),
              versionValue.intValue == 1,
              let rawKeys = object["keys"] as? [Any] else {
            return nil
        }
        let keys = rawKeys.compactMap { $0 as? String }.filter { !$0.isEmpty }
        guard !keys.isEmpty, keys.count == rawKeys.count else { return nil }

        let rawCaption = (object["caption"] as? String) ?? ""
        let caption = normalizedCaption(text: rawCaption, mentions: object["captionMentions"])
        return E2EESealedMediaPayload(
            keys: keys,
            caption: caption?.text,
            captionMentions: caption?.mentions
        )
    }

    /// Caption normalization: blank text means no caption, and mention spans survive
    /// only when their slice of the text really reads "@name" (validateMentionSpans).
    static func normalizedCaption(text: String, mentions: Any?) -> (text: String, mentions: [E2EEMentionSpan]?)? {
        guard text.contains(where: { !$0.isWhitespace }) else { return nil }
        var valid: [E2EEMentionSpan] = []
        if let rawSpans = mentions as? [[String: Any]] {
            let characters = Array(text)
            for raw in rawSpans {
                guard let jid = raw["jid"] as? String,
                      let name = raw["name"] as? String,
                      let offset = raw["offset"] as? Int,
                      let length = raw["length"] as? Int,
                      offset >= 0, length >= 0, offset + length <= characters.count else { continue }
                let slice = String(characters[offset..<(offset + length)])
                if slice == "@\(name)" {
                    valid.append(E2EEMentionSpan(jid: jid, name: name, offset: offset, length: length))
                }
            }
        }
        return (text, valid.isEmpty ? nil : valid)
    }

    // MARK: - JSON

    /// JSON.stringify of {mimetype, originalname, size}, written by hand so the key
    /// order and escaping match the web byte for byte.
    static func headerJSON(_ meta: E2EEFileMeta) -> String {
        "{\"mimetype\":\(jsonString(meta.mimetype)),\"originalname\":\(jsonString(meta.originalname)),\"size\":\(meta.size)}"
    }

    static func jsonString(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }
}
