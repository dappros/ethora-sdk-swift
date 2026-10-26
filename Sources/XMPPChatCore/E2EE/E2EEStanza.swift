//
//  E2EEStanza.swift
//  XMPPChatCore
//
//  Turns an OMEMO stanza back into an ordinary one. Translated from
//  ethora-chat-component/src/e2ee/stanza.ts. The rewrite is done on a copy: <encrypted>
//  is replaced by the children of the SCE envelope, so everything downstream (message
//  parser, reaction, edit and history handlers, the room store) sees exactly the stanza
//  an unencrypted sender would have produced.
//

import Foundation

/// What the receive seam did with a stanza.
enum E2EEStanzaOutcome {
    /// No OMEMO payload; the caller carries on as before.
    case notEncrypted(XMPPStanza)
    /// Rewritten with the sender's original children.
    case decrypted(XMPPStanza)
    /// Rewritten with a placeholder body; still a message worth showing.
    case undecryptable(XMPPStanza)
    /// Session maintenance only: nothing to render.
    case drop
}

enum E2EEStanza {

    /// Max depth searched for the carrier message (mucsub event, MAM result, or both).
    private static let maxDepth = 4

    /// Path of child indexes to the <message> that carries <encrypted>. The empty path is
    /// the stanza itself. Nil when there is no OMEMO payload anywhere in the stanza.
    static func carrierPath(_ stanza: XMPPStanza, depth: Int = 0) -> [Int]? {
        guard depth <= maxDepth else { return nil }
        if stanza.name == "message", stanza.child("encrypted", xmlns: E2EEConstants.nsOmemo) != nil {
            return []
        }
        for (index, child) in stanza.children.enumerated() {
            if let rest = carrierPath(child, depth: depth + 1) {
                return [index] + rest
            }
        }
        return nil
    }

    /// Decrypts the carrier inside `stanza`, if it carries OMEMO at all. Safe on every
    /// message: without an OMEMO payload it returns `.notEncrypted` and touches nothing.
    static func decryptInPlace(_ stanza: XMPPStanza, domain: String) async -> E2EEStanzaOutcome {
        guard let path = carrierPath(stanza) else { return .notEncrypted(stanza) }
        let carrier = node(stanza, path: path[...])
        guard let encrypted = carrier.child("encrypted", xmlns: E2EEConstants.nsOmemo) else {
            return .notEncrypted(stanza)
        }
        // No payload: a session-maintenance message. It must not reach the handlers.
        guard encrypted.child("payload") != nil else { return .drop }

        let from = carrier.attributes["from"] ?? ""
        let roomJid = String(from.split(separator: "/", maxSplits: 1).first ?? "")
        let sender = E2EEManager.senderJid(fromMuc: from, domain: domain)

        var decrypted: E2EEDecrypted?
        if let sender, let omemo = await E2EEManager.shared.ready() {
            do {
                decrypted = try await omemo.decrypt(carrier: carrier, sender: sender, roomJid: roomJid)
            } catch {
                decrypted = E2EEDecrypted(content: nil, trust: .untrusted, error: "omemo_decrypt_failed")
            }
        }

        // The fallback <body> and the OMEMO elements exist for clients that cannot decrypt.
        // Even on failure the placeholder beats the fallback: it distinguishes "encrypted for
        // another device" from "we could not open this".
        var rewritten = carrier
        rewritten.children.removeAll { child in
            (child.name == "encrypted" && child.attributes["xmlns"] == E2EEConstants.nsOmemo)
                || (child.name == "encryption" && child.attributes["xmlns"] == "urn:xmpp:eme:0")
                || child.name == "body"
        }

        let readable: Bool
        if let content = decrypted?.content, !content.isEmpty {
            if let wrapper = XMPPStanzaParser.parse("<omemo-content>\(content)</omemo-content>") {
                rewritten.children.append(contentsOf: wrapper.children)
            }
            liftSealedMedia(into: &rewritten)
            readable = true
        } else {
            rewritten.children.append(placeholder(error: decrypted?.error))
            readable = false
        }

        // Marks the message as having arrived encrypted, which is true on both branches,
        // including the one we could not read. <data> is the channel: it rides in the clear.
        markEncrypted(&rewritten)
        let whole = replacing(stanza, path: path[...], with: rewritten)
        return readable ? .decrypted(whole) : .undecryptable(whole)
    }

    // MARK: - Helpers

    private static func placeholder(error: String?) -> XMPPStanza {
        let text = error == "omemo_not_encrypted_for_this_device"
            ? "Encrypted for another device"
            : "Could not decrypt this message"
        return XMPPStanza(name: "body", text: text)
    }

    private static func markEncrypted(_ carrier: inout XMPPStanza) {
        if let index = carrier.children.firstIndex(where: { $0.name == "data" }) {
            carrier.children[index].attributes["omemoEncrypted"] = "true"
        } else {
            carrier.children.append(XMPPStanza(name: "data", attributes: ["omemoEncrypted": "true"]))
        }
    }

    /// A sealed media <body> carries `{"v":1,"keys":[...]}`. Lift the keys onto <data> as
    /// `e2eeKeys` (a JSON array string) and make the body the ordinary media placeholder.
    private static func liftSealedMedia(into carrier: inout XMPPStanza) {
        guard let bodyIndex = carrier.children.firstIndex(where: { $0.name == "body" }) else { return }
        let bodyText = carrier.children[bodyIndex].text
        guard let sealed = E2EEFileEnvelope.parseSealedMediaPayload(bodyText) else { return }
        carrier.children[bodyIndex].text = "media"
        let keysJSON = "[" + sealed.keys.map(E2EEFileEnvelope.jsonString).joined(separator: ",") + "]"
        if let dataIndex = carrier.children.firstIndex(where: { $0.name == "data" }) {
            carrier.children[dataIndex].attributes["e2eeKeys"] = keysJSON
            if let caption = sealed.caption {
                carrier.children[dataIndex].attributes["caption"] = caption
            }
        } else {
            var attributes = ["e2eeKeys": keysJSON]
            if let caption = sealed.caption { attributes["caption"] = caption }
            carrier.children.append(XMPPStanza(name: "data", attributes: attributes))
        }
    }

    static func node(_ root: XMPPStanza, path: ArraySlice<Int>) -> XMPPStanza {
        guard let first = path.first else { return root }
        return node(root.children[first], path: path.dropFirst())
    }

    static func replacing(_ root: XMPPStanza, path: ArraySlice<Int>, with replacement: XMPPStanza) -> XMPPStanza {
        guard let first = path.first else { return replacement }
        var copy = root
        copy.children[first] = replacing(root.children[first], path: path.dropFirst(), with: replacement)
        return copy
    }
}
