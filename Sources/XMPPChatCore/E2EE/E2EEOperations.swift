//
//  E2EEOperations.swift
//  XMPPChatCore
//
//  Outgoing seam for the XMPPOperations send functions. Each caller decides what a
//  failure means: text falls back to plaintext (as the web does), sealed media and
//  edits refuse to send in clear.
//

import Foundation

extension XMPPOperations {

    /// The encrypted groupchat stanza for `roomJID`, or nil when the room is not e2ee
    /// (or encryption is off). Throws when the room is e2ee but cannot be encrypted.
    func e2eeEncryptedStanza(
        roomJID: String,
        id: String,
        content: [XMPPStanza],
        cleartext: [XMPPStanza],
        domain: String
    ) async throws -> XMPPStanza? {
        guard await E2EEManager.isE2eeRoom(roomJID) else { return nil }
        guard let omemo = await E2EEManager.shared.ready() else {
            throw E2EEOmemoError.notReady
        }
        let members = await E2EEManager.roomRecipients(roomJID, domain: domain)
        return try await omemo.encryptGroupMessage(
            roomJid: roomJID,
            members: members,
            content: content,
            id: id,
            cleartext: cleartext
        )
    }
}
