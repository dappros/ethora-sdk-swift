//
//  ChatStates.swift
//  XMPPChatCore
//
//  Typing indicator (XEP-0085 chat states) stanzas. Wire shape mirrors
//  ethora-chat-component sendTypingRequest.xmpp.ts: a groupchat message with
//  <composing|paused/> plus <data fullName="..."/>.
//

import Foundation

public enum XMPPChatStateStanzas {
    public static func typing(chatId: String, fullName: String, start: Bool, id: String) -> XMPPStanza {
        XMPPStanza(
            name: "message",
            attributes: ["type": "groupchat", "id": id, "to": chatId],
            children: [
                XMPPStanza(
                    name: start ? "composing" : "paused",
                    attributes: ["xmlns": "http://jabber.org/protocol/chatstates"]
                ),
                XMPPStanza(name: "data", attributes: ["fullName": fullName]),
            ]
        )
    }

    /// True for a typing stanza, so it never reaches the message pipeline.
    public static func isChatState(_ stanza: XMPPStanza) -> Bool {
        stanza.children.contains { $0.name == "composing" || $0.name == "paused" }
    }
}
