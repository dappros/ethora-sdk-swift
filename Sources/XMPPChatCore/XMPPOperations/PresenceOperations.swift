//
//  PresenceOperations.swift
//  XMPPChatCore
//
//  Translated from presenceInRoom.xmpp.ts and allRoomPresences.xmpp.ts
//

import Foundation

extension XMPPOperations {
    /// Send presence to a room (presenceInRoom from TypeScript)
    /// TypeScript: to: `${roomJID}/${client.jid?.getLocal()}`
    /// We use firstName + lastName as nickname (from UserStore)
    public func presenceInRoom(roomJID: String, settleDelay: TimeInterval = 0) async {
        guard let stream = client?.xmppStream else { return }
        guard let jid = stream.jid else {
            NSLog("❌ Cannot send presence - no JID available")
            print("❌ Cannot send presence - no JID available")
            return
        }
        
        // Check if we've already received a presence response for this room
        // Extract bare JID (without resource) for comparison
        let bareRoomJID = roomJID.components(separatedBy: "/").first ?? roomJID
        if client?.hasPresenceResponseForRoom(bareRoomJID) == true {
            print("⏭️ Skipping presence send to room '\(bareRoomJID)' - already received response")
            return
        }
        
        // Match TypeScript: to: `${roomJID}/${client.jid?.getLocal()}`
        // TypeScript uses client.jid?.getLocal() which is the username (local part of JID)
        // This is the XMPP username, NOT firstName + lastName
        let username = jid.components(separatedBy: "@").first ?? ""
        let toJID = "\(roomJID)/\(username)"
        
        // Match TypeScript: from: client.jid?.toString()
        // Match TypeScript: id: 'presenceInRoom'
        // Match TypeScript: xml('x', { xmlns: 'http://jabber.org/protocol/muc' })
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
        
        stream.send(presenceStanza)
        NSLog("📤 Sent presence to room: %@ (nickname: %@)", roomJID, username)
        print("📤 Sent presence to room: \(roomJID) (nickname: \(username))")
    }
    
    /// Send presence to all rooms (allRoomPresences from TypeScript)
    /// Note: This requires access to the rooms list, which should come from RoomListViewModel or similar
    public func allRoomPresences(roomJIDs: [String]) async {
        // Match TypeScript: await Promise.all(Object.keys(rooms).map((roomJid) => presenceInRoom(client, roomJid)))
        await withTaskGroup(of: Void.self) { group in
            for roomJID in roomJIDs {
                group.addTask {
                    await self.presenceInRoom(roomJID: roomJID)
                }
            }
        }
        NSLog("✅ Sent presence to %lu rooms", roomJIDs.count)
        print("✅ Sent presence to \(roomJIDs.count) rooms")
    }
}

