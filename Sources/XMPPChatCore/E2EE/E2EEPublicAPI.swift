//
//  E2EEPublicAPI.swift
//  XMPPChatCore
//
//  The public surface of end-to-end encryption for host apps and XMPPChatUI.
//  Everything else in E2EE/ stays internal.
//

import Foundation

/// A file sealed for upload in an e2ee room.
public struct E2EESealedUpload: Equatable {
    /// Ciphertext to upload as application/octet-stream with clientEncrypted=true.
    public let ciphertext: Data
    /// Base64 key material; belongs in the encrypted message body.
    public let keyMaterial: String
    /// Random, extension-free name to upload under.
    public let filename: String
}

public enum E2EE {

    /// True when encryption is enabled and the backend marked the room `e2ee`.
    public static func isRoomEncrypted(_ roomJid: String) async -> Bool {
        await E2EEManager.isE2eeRoom(roomJid)
    }

    /// Seals a file so the server only ever stores ciphertext.
    public static func sealFileForUpload(bytes: Data, mimetype: String?, originalName: String?) throws -> E2EESealedUpload {
        let sealed = try E2EEFileEnvelope.sealForUpload(bytes: bytes, mimetype: mimetype, originalName: originalName)
        return E2EESealedUpload(ciphertext: sealed.ciphertext, keyMaterial: sealed.keyMaterial, filename: sealed.filename)
    }
}
