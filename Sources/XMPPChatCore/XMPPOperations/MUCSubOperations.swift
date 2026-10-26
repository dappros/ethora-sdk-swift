//
//  MUCSubOperations.swift
//  XMPPChatCore
//
//  MUCSub (XEP-0045 + XEP-0048) room push subscription.
//  Stanza shape from src/networking/xmpp/subscribeToRoomMessages.xmpp.ts:
//    <iq to=room type="set" id="newSubscription:<ms>">
//      <subscribe xmlns="urn:xmpp:mucsub:0" nick=nick><event node="urn:xmpp:mucsub:nodes:messages"/></subscribe>
//    </iq>
//

import Foundation

/// Pure stanza builder, so the wire shape can be tested without a socket.
public enum MUCSubStanza {
    public static let messagesNode = "urn:xmpp:mucsub:nodes:messages"

    /// `id` defaults to `newSubscription:<unix ms>`, the same form web uses.
    public static func subscribeIQ(
        roomJID: String,
        nick: String? = nil,
        node: String = messagesNode,
        id: String? = nil
    ) -> XMPPStanza {
        let stanzaId = id ?? "newSubscription:\(Int64(Date().timeIntervalSince1970 * 1000))"

        var subscribeAttributes: [String: String] = ["xmlns": "urn:xmpp:mucsub:0"]
        if let nick, !nick.isEmpty {
            subscribeAttributes["nick"] = nick
        }

        let event = XMPPStanza(name: "event", attributes: ["node": node])
        let subscribe = XMPPStanza(name: "subscribe", attributes: subscribeAttributes, children: [event])
        return XMPPStanza(
            name: "iq",
            attributes: ["to": roomJID, "type": "set", "id": stanzaId],
            children: [subscribe]
        )
    }
}

extension XMPPOperations {
    /// Subscribe to room message events for push notifications via MUCSub
    /// - Parameters:
    ///   - roomJID: Room JID ("room@conference.example.com") or room name
    ///   - nick: Optional nick for subscription
    ///   - node: MUCSub node (default: messages)
    ///   - id: Optional IQ id override
    /// - Returns: IQ id used for the subscription (or nil if not connected)
    @discardableResult
    public func subscribeToRoomPush(
        roomJID: String,
        nick: String? = nil,
        node: String = MUCSubStanza.messagesNode,
        id: String? = nil
    ) -> String? {
        guard let stream = client?.xmppStream else {
            return nil
        }

        // `client.conference` is set from `XMPPSettings.conference` in
        // the failable XMPPClient init — if no client is attached we
        // bail rather than substituting a hardcoded production value.
        guard let conferenceDomain = client?.conference, !conferenceDomain.isEmpty else {
            return nil
        }
        let fixedRoomJID = roomJID.contains("@") ? roomJID : "\(roomJID)@\(conferenceDomain)"

        let iq = MUCSubStanza.subscribeIQ(roomJID: fixedRoomJID, nick: nick, node: node, id: id)
        stream.send(iq)
        return iq.attributes["id"]
    }
}
