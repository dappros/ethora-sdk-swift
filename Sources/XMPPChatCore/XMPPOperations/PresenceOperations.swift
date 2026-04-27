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
    
    /// Leave a MUC room — sends `<presence type="unavailable"
    /// to="room/nick"/>` (XEP-0045, §7.14). Web does exactly this in
    /// the "Leave" menu, per the user-supplied log:
    ///   <presence to="…@conference.…/nickname" type="unavailable"/>
    /// This does NOT destroy the room on the server — it stays alive;
    /// this client just stops being an occupant and no longer receives
    /// broadcasts (and ejabberd drops the mucsub subscription for this
    /// resource as a side effect).
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

        // In case the user later re-joins the same room in this session:
        // clear the "presence ack received" flag so the next
        // `presenceInRoom` for this JID actually goes out instead of
        // being short-circuited by the early return.
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
