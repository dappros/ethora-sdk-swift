//
//  PresenceOperations.swift
//  XMPPChatCore
//
//

import Foundation

extension XMPPOperations {
    /// Send presence to a room (presenceInRoom from TypeScript)
    /// TypeScript: to: `${roomJID}/${client.jid?.getLocal()}`
    /// We use firstName + lastName as nickname (from UserStore)
    public func presenceInRoom(roomJID: String, settleDelay: TimeInterval = 0) async {
        guard let stream = client?.xmppStream else { return }
        guard let jid = stream.jid else {
            //NSlog("❌ Cannot send presence - no JID available")
            //print("❌ Cannot send presence - no JID available")
            return
        }
        
        // Check if we've already received a presence response for this room
        // Extract bare JID (without resource) for comparison
        let bareRoomJID = roomJID.components(separatedBy: "/").first ?? roomJID
        if client?.hasPresenceResponseForRoom(bareRoomJID) == true {
            print("⏭️ [XMPP] Skipping room presence (already acknowledged): \(bareRoomJID)")
            return
        }
        
        // Use nickname derived from the connected JID localpart (TypeScript: `jid.getLocal()`).
        // Some MUC servers require occupant nick to match user identity *without* the domain part.
        let bareJid = jid.components(separatedBy: "/").first ?? jid
        let nick = bareJid.components(separatedBy: "@").first ?? bareJid
        let toJID = "\(bareRoomJID)/\(nick)"
        
        // Match Android SDK (XMPPWebSocketConnection.kt:1699 / XMPPClient.kt) verbatim:
        // include `from` with the full connected JID (localpart@host/resource).
        // ethora's ejabberd MUC rejects joins without an explicit non-anonymous
        // `from` with `<forbidden/>` "anonymous not allowed" — omitting it is
        // the last wire-level divergence observed against the working Android
        // path. The wire diagnostic log shows handshake + SASL PLAIN succeed
        // cleanly and a real user JID is bound, so the issue is at MUC-join
        // level, not auth level.
        let presenceStanza = XMPPStanza(
            name: "presence",
            attributes: [
                "from": jid,
                "to": toJID,
                "id": "presenceInRoom"
            ],
            children: [
                XMPPStanza(
                    name: "x",
                    attributes: [
                        "xmlns": "http://jabber.org/protocol/muc"
                    ]
                )
            ]
        )
        
        if settleDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(settleDelay * 1_000_000_000))
        }
        
        print("📤 [XMPP] Sending room presence")
        print("   from: \(jid)")
        print("   to:   \(toJID)")
        print("   id:   presenceInRoom")
        stream.send(presenceStanza)
        print("✅ [XMPP] Room presence stanza sent")
    }
    
    /// Покинуть комнату MUC — посылаем `<presence type="unavailable"
    /// to="room/nick"/>` (XEP-0045, §7.14). Web делает то же самое в
    /// меню «Leave», см. лог пользователя:
    ///   <presence to="…@conference.…/nickname" type="unavailable"/>
    /// Это НЕ разрушает комнату на сервере — она остаётся, просто этот
    /// клиент перестаёт быть occupant'ом и больше не получает broadcast'ы
    /// (а заодно ejabberd снимает mucsub-подписку для этого ресурса).
    public func leaveRoom(roomJID: String) async {
        guard let stream = client?.xmppStream else { return }
        guard let jid = stream.jid else {
            print("❌ Cannot send leave presence — no JID available")
            return
        }

        let bareRoomJID = roomJID.components(separatedBy: "/").first ?? roomJID
        let bareJid = jid.components(separatedBy: "/").first ?? jid
        let nick = bareJid.components(separatedBy: "@").first ?? bareJid
        let toJID = "\(bareRoomJID)/\(nick)"

        let stanza = XMPPStanza(
            name: "presence",
            attributes: [
                "from": jid,
                "to": toJID,
                "type": "unavailable"
            ]
        )

        print("📤 [XMPP] Leaving room \(bareRoomJID) — <presence type='unavailable' to='\(toJID)'/>")
        stream.send(stanza)

        // На случай повторного захода в эту же комнату дальше по сессии:
        // сбрасываем флаг «присутствие подтверждено», чтобы следующий
        // `presenceInRoom` для этого JID реально ушёл, а не отбросился
        // ранним return-ом.
        await MainActor.run {
            client?.clearPresenceResponse(forRoom: bareRoomJID)
        }
    }

    /// Send presence to all rooms (allRoomPresences from TypeScript)
    /// Note: This requires access to the rooms list, which should come from RoomListViewModel or similar
    public func allRoomPresences(roomJIDs: [String]) async {
        // Send sequentially to avoid server flood/disconnect on large room lists.
        for (index, roomJID) in roomJIDs.enumerated() {
            await self.presenceInRoom(roomJID: roomJID)
            if index < roomJIDs.count - 1 {
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }
        //NSlog("✅ Sent presence to %lu rooms", roomJIDs.count)
        //print("✅ Sent presence to \(roomJIDs.count) rooms")
    }
}
