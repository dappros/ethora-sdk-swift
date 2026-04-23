//
//  MUCSubOperations.swift
//  XMPPChatCore
//
//  MUCSub (XEP-0045 + XEP-0048) room push subscription
//

import Foundation

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
        node: String = "urn:xmpp:mucsub:nodes:messages",
        id: String? = nil
    ) -> String? {
        guard let stream = client?.xmppStream else {
            return nil
        }

        let conferenceDomain = client?.conference ?? "conference.xmpp.messenger-dev2.vitall.com"
        let fixedRoomJID = roomJID.contains("@") ? roomJID : "\(roomJID)@\(conferenceDomain)"

        let stanzaId = id ?? "mucsub:\(Int64(Date().timeIntervalSince1970 * 1000))"

        var subscribeAttributes: [String: String] = [
            "xmlns": "urn:xmpp:mucsub:0"
        ]
        if let nick = nick, !nick.isEmpty {
            subscribeAttributes["nick"] = nick
        }

        let eventStanza = XMPPStanza(
            name: "event",
            attributes: ["node": node]
        )

        let subscribeStanza = XMPPStanza(
            name: "subscribe",
            attributes: subscribeAttributes,
            children: [eventStanza]
        )

        let iqStanza = XMPPStanza(
            name: "iq",
            attributes: [
                "to": fixedRoomJID,
                "type": "set",
                "id": stanzaId
            ],
            children: [subscribeStanza]
        )

        stream.send(iqStanza)
        return stanzaId
    }
}
