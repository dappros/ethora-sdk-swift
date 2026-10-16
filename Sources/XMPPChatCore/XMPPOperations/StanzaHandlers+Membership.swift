//
//  StanzaHandlers+Membership.swift
//  XMPPChatCore
//
//  Live membership changes for a room: the <message> path and the occupant
//  <presence> path. Translated from src/networking/stanzaHandlers.ts
//  (onRoomMembershipChange and the membership branch of onPresenceInRoom).
//

import Foundation

extension StanzaHandlers {
    static let mucUserNamespace = "http://jabber.org/protocol/muc#user"

    /// Membership change sent as a groupchat-style <message> to the occupants:
    /// `<x xmlns="muc#user"><item jid="..." affiliation="member|none|outcast"/></x>`.
    /// Invites (a child <invite/>) are not membership changes and are skipped.
    public func onRoomMembershipChange(_ stanza: XMPPStanza) {
        guard stanza.name == "message" else { return }
        let roomJID = (stanza.attributes["from"] ?? "").components(separatedBy: "/").first ?? ""
        guard !roomJID.isEmpty else { return }

        guard let x = stanza.getChildren("x").first(where: { $0.attributes["xmlns"] == StanzaHandlers.mucUserNamespace }),
              x.getChild("invite") == nil,
              let item = x.getChild("item") else { return }
        let memberJid = item.attributes["jid"] ?? ""
        guard !memberJid.isEmpty else { return }
        let xmppUsername = memberJid.components(separatedBy: "@").first ?? ""
        let affiliation = item.attributes["affiliation"] ?? ""

        Task { @MainActor in
            guard let room = RoomStore.shared.rooms[roomJID] else { return }
            let update = RoomMembership.messageUpdate(
                room: room,
                xmppUsername: xmppUsername,
                memberJid: memberJid,
                affiliation: affiliation
            )
            RoomMembershipApplier.apply(update, roomJID: roomJID)
        }
    }

    /// Occupant presence from someone else: `from="room@conf/nick"` with a muc#user item.
    /// A persistent affiliation on a join counts as a join; a none/outcast
    /// unavailable counts as a kick or leave. Our own presence is ignored here
    /// (it is handled by `onPresenceInRoom`).
    public func onOccupantPresence(_ stanza: XMPPStanza, ownNick: String) {
        guard stanza.name == "presence", stanza.getChild("error") == nil else { return }
        let from = stanza.attributes["from"] ?? ""
        guard let slash = from.firstIndex(of: "/") else { return }
        let roomJID = String(from[..<slash])
        let nick = String(from[from.index(after: slash)...])
        guard !roomJID.isEmpty, !nick.isEmpty, nick != ownNick else { return }

        guard let x = stanza.getChildren("x").first(where: { $0.attributes["xmlns"] == StanzaHandlers.mucUserNamespace }),
              let item = x.getChild("item") else { return }
        let affiliation = item.attributes["affiliation"] ?? ""
        let isUnavailable = stanza.attributes["type"] == "unavailable"

        Task { @MainActor in
            guard let room = RoomStore.shared.rooms[roomJID] else { return }
            let update = RoomMembership.presenceUpdate(
                room: room,
                nickname: nick,
                affiliation: affiliation,
                isUnavailable: isUnavailable
            )
            RoomMembershipApplier.apply(update, roomJID: roomJID)
        }
    }
}
