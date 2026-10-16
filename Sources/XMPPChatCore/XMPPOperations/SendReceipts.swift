//
//  SendReceipts.swift
//  XMPPChatCore
//
//  XEP-0184 delivery receipts and XEP-0333 displayed markers. Wire shape and
//  send rules mirror ethora-chat-component (sendReceivedReceipt.xmpp.ts,
//  sendDisplayedMarker.xmpp.ts, xmppClient.historyReceipt).
//

import Foundation

extension XMPPOperations {
    /// Tells the room that `messageId` reached this client (XEP-0184).
    public func sendReceivedReceipt(roomJID: String, messageId: String) {
        guard let stream = client?.xmppStream else { return }
        let id = "message-received:\(Int64(Date().timeIntervalSince1970 * 1000))"
        stream.send(XMPPReceiptStanzas.receivedReceipt(
            from: stream.jid ?? "",
            roomJID: roomJID,
            messageId: messageId,
            id: id
        ))
    }

    /// Tells the room this client has displayed up to `messageId` (XEP-0333).
    public func sendDisplayedMarker(roomJID: String, messageId: String) {
        guard let stream = client?.xmppStream else { return }
        let id = "message-displayed:\(Int64(Date().timeIntervalSince1970 * 1000))"
        stream.send(XMPPReceiptStanzas.displayedMarker(
            from: stream.jid ?? "",
            roomJID: roomJID,
            messageId: messageId,
            id: id
        ))
    }
}

/// Pure stanza builders for receipts and markers. Kept apart from the send
/// methods so the wire shape can be round-trip tested without a socket.
public enum XMPPReceiptStanzas {
    public static func receivedReceipt(from: String, roomJID: String, messageId: String, id: String) -> XMPPStanza {
        XMPPStanza(
            name: "message",
            attributes: ["id": id, "type": "groupchat", "from": from, "to": roomJID],
            children: [
                XMPPStanza(name: "received", attributes: [
                    "xmlns": "urn:xmpp:receipts",
                    "id": messageId,
                    "from": from,
                ]),
                XMPPStanza(name: "store", attributes: ["xmlns": "urn:xmpp:hints"]),
            ]
        )
    }

    public static func displayedMarker(from: String, roomJID: String, messageId: String, id: String) -> XMPPStanza {
        XMPPStanza(
            name: "message",
            attributes: ["id": id, "type": "groupchat", "from": from, "to": roomJID],
            children: [
                XMPPStanza(name: "displayed", attributes: [
                    "xmlns": "urn:xmpp:chat-markers:0",
                    "id": messageId,
                    "from": from,
                ]),
                XMPPStanza(name: "store", attributes: ["xmlns": "urn:xmpp:hints"]),
            ]
        )
    }
}

/// Decides which incoming messages get a delivery receipt.
public enum ReceiptPolicy {
    /// Bare nickname or JID local part: `alice@host/res` and `alice` both give `alice`.
    public static func localPart(_ jidOrNick: String) -> String {
        jidOrNick.components(separatedBy: "/").first?.components(separatedBy: "@").first ?? ""
    }

    /// Same user by web's rule: case-insensitive, underscores ignored.
    public static func isSameUser(_ a: String, _ b: String) -> Bool {
        let na = localPart(a).lowercased().replacingOccurrences(of: "_", with: "")
        let nb = localPart(b).lowercased().replacingOccurrences(of: "_", with: "")
        return !na.isEmpty && na == nb
    }

    /// Mirrors web onRealtimeMessage: ack only messages from someone else,
    /// never system messages, and only when there is something visible
    /// (text body or media). Own echoes and empty chat-state frames are skipped.
    public static func shouldAcknowledge(_ message: Message, selfUsername: String) -> Bool {
        let sender = message.user.xmppUsername ?? message.user.id
        if isSameUser(sender, selfUsername) { return false }
        if message.isSystemMessage == "true" { return false }
        let hasBody = !message.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasBody || message.isMediafile == "true"
    }
}

/// Dedupe for receipts sent on MAM catch-up, so repeated fetches of the same
/// page do not re-ack. FIFO-capped like web (`maxHistoryReceiptAckedIds`).
public struct HistoryReceiptLedger {
    private var order: [String] = []
    private var seen: Set<String> = []
    private let capacity: Int

    public init(capacity: Int = 2000) {
        self.capacity = capacity
    }

    /// Returns `true` the first time a room and message pair is seen.
    public mutating func insert(roomJID: String, messageId: String) -> Bool {
        let key = "\(roomJID):\(messageId)"
        guard !seen.contains(key) else { return false }
        seen.insert(key)
        order.append(key)
        if order.count > capacity {
            seen.remove(order.removeFirst())
        }
        return true
    }
}
