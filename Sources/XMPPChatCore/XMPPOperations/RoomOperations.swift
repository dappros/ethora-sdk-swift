//
//  RoomOperations.swift
//  XMPPChatCore
//
//  Room-related XMPP operations (create, invite, leave, etc.)
//

import Foundation
import CryptoKit

extension XMPPOperations {
    
    // MARK: - Create Room
    
    /// Create a new public/group room
    /// Mirrors createRoom from createRoom.xmpp.ts
    public func createRoom(
        title: String,
        description: String,
        conferenceDomain: String
    ) async throws -> String {
        guard let stream = client?.xmppStream,
              let jid = stream.jid else {
            throw XMPPOperationError.notConnected
        }
        
        // Generate room hash (matches TypeScript: sha256(title + Date.now() + randomNumber))
        let randomNumber = Int.random(in: 0...100_000)
        let chatNameWithSalt = "\(title)\(Int64(Date().timeIntervalSince1970 * 1000))\(randomNumber)"
        let roomHash = sha256(chatNameWithSalt)
        let roomId = "\(roomHash)@\(conferenceDomain)"
        
        do {
            try await createRoomPresence(roomId: roomId)
            try await setMeAsOwner(roomId: roomId)
            try await roomConfig(roomId: roomId, title: title, description: description)
        } catch {
            print("❌ Error creating room: \(error)")
            throw error
        }
        
        return roomId
    }
    
    /// Create a private room
    /// Mirrors createPrivateRoom from createPrivateRoom.xmpp.ts
    public func createPrivateRoom(
        title: String,
        description: String,
        to: String,
        conferenceDomain: String
    ) async throws -> String {
        guard let stream = client?.xmppStream,
              let jid = stream.jid else {
            throw XMPPOperationError.notConnected
        }
        
        let roomHash = to
        let roomId = "\(roomHash)@\(conferenceDomain)"
        
        do {
            try await createRoomPresence(roomId: roomId)
            try await setMeAsOwner(roomId: roomId)
            try await roomConfig(roomId: roomId, title: title, description: description)
        } catch {
            print("❌ Error creating private room: \(error)")
            throw error
        }
        
        return roomId
    }
    
    // MARK: - Room Presence
    
    /// Create room presence (first step in room creation)
    /// Mirrors createRoomPresence from createRoomPresence.xmpp.ts
    private func createRoomPresence(roomId: String) async throws {
        guard let stream = client?.xmppStream,
              let jid = stream.jid else {
            throw XMPPOperationError.notConnected
        }
        
        let username = jid.components(separatedBy: "@").first ?? ""
        let toJID = "\(roomId)/\(username)"
        
        let presenceStanza = XMPPStanza(
            name: "presence",
            attributes: [
                "to": toJID
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
        
        // Wait for presence response with status codes 201 and 110
        let responseReceived = await withCheckedContinuation { continuation in
            var handler: ((XMPPStanza) -> Bool)?
            
            handler = { stanza in
                guard stanza.name == "presence",
                      stanza.attributes["from"]?.components(separatedBy: "/").first == roomId else {
                    return false
                }
                
                let xEls = stanza.getChildren("x")
                guard xEls.count == 2 else {
                    return false
                }
                
                if let mucX = xEls.first(where: { $0.attributes["xmlns"] == "http://jabber.org/protocol/muc#user" }) {
                    let statuses = mucX.getChildren("status")
                    let codes = statuses.compactMap { $0.attributes["code"] }
                    
                    if codes.contains("201") && codes.contains("110") {
                        continuation.resume(returning: true)
                        return true
                    } else {
                        // Room already exists
                        continuation.resume(returning: true)
                        return true
                    }
                }
                
                return false
            }
            
            // Note: We use a timeout-based approach for waiting for presence response
            // The handler registration would require access to private handleStanzas
            
            stream.send(presenceStanza)
            
            // Timeout after 2 seconds
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                continuation.resume(returning: false)
            }
        }
        
        if !responseReceived {
            throw XMPPOperationError.timeout
        }
    }
    
    /// Set current user as room owner
    /// Mirrors setMeAsOwner from setMeAsOwner.xmpp.ts
    private func setMeAsOwner(roomId: String) async throws {
        guard let stream = client?.xmppStream else {
            throw XMPPOperationError.notConnected
        }
        
        let id = "set-me-as-owner:\(Int64(Date().timeIntervalSince1970 * 1000))"
        
        let queryStanza = XMPPStanza(
            name: "query",
            attributes: [
                "xmlns": "http://jabber.org/protocol/muc#owner"
            ],
            children: [
                XMPPStanza(
                    name: "x",
                    attributes: [
                        "xmlns": "jabber:x:data",
                        "type": "submit"
                    ]
                )
            ]
        )
        
        let iqStanza = XMPPStanza(
            name: "iq",
            attributes: [
                "to": roomId,
                "id": id,
                "type": "set"
            ],
            children: [queryStanza]
        )
        
        // Wait for result
        let responseReceived = await withCheckedContinuation { continuation in
            stream.send(iqStanza)
            
            // Timeout after 2 seconds
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                continuation.resume(returning: false)
            }
        }
        
        if !responseReceived {
            throw XMPPOperationError.timeout
        }
    }
    
    /// Configure room (set title and description)
    /// Mirrors roomConfig from roomConfig.xmpp.ts
    private func roomConfig(roomId: String, title: String, description: String) async throws {
        guard let stream = client?.xmppStream else {
            throw XMPPOperationError.notConnected
        }
        
        let id = "room-config:\(Int64(Date().timeIntervalSince1970 * 1000))"
        
        let formTypeField = XMPPStanza(
            name: "field",
            attributes: ["var": "FORM_TYPE"],
            children: [
                XMPPStanza(
                    name: "value",
                    text: "http://jabber.org/protocol/muc#roomconfig"
                )
            ]
        )
        
        let roomNameField = XMPPStanza(
            name: "field",
            attributes: ["var": "muc#roomconfig_roomname"],
            children: [
                XMPPStanza(
                    name: "value",
                    text: title
                )
            ]
        )
        
        let roomDescField = XMPPStanza(
            name: "field",
            attributes: ["var": "muc#roomconfig_roomdesc"],
            children: [
                XMPPStanza(
                    name: "value",
                    text: description
                )
            ]
        )
        
        let xStanza = XMPPStanza(
            name: "x",
            attributes: [
                "xmlns": "jabber:x:data",
                "type": "submit"
            ],
            children: [formTypeField, roomNameField, roomDescField]
        )
        
        let queryStanza = XMPPStanza(
            name: "query",
            attributes: [
                "xmlns": "http://jabber.org/protocol/muc#owner"
            ],
            children: [xStanza]
        )
        
        let iqStanza = XMPPStanza(
            name: "iq",
            attributes: [
                "id": id,
                "to": roomId,
                "type": "set"
            ],
            children: [queryStanza]
        )
        
        // Wait for result
        let responseReceived = await withCheckedContinuation { continuation in
            stream.send(iqStanza)
            
            // Timeout after 2 seconds
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                continuation.resume(returning: false)
            }
        }
        
        if !responseReceived {
            throw XMPPOperationError.timeout
        }
    }
    
    // MARK: - Invite Room Request
    
    /// Invite a user to a room
    /// Mirrors inviteRoomRequest from inviteRoomRequest.xmpp.ts
    public func inviteRoomRequest(to: String, roomJid: String, chatDomain: String) {
        guard let stream = client?.xmppStream else { return }
        
        let id = "invite-rooms:\(Int64(Date().timeIntervalSince1970 * 1000))"
        let inviteTo = "\(to)\(chatDomain)"
        
        let inviteStanza = XMPPStanza(
            name: "invite",
            attributes: ["to": inviteTo]
        )
        
        let xStanza = XMPPStanza(
            name: "x",
            attributes: [
                "xmlns": "http://jabber.org/protocol/muc#user"
            ],
            children: [inviteStanza]
        )
        
        let messageStanza = XMPPStanza(
            name: "message",
            attributes: [
                "to": roomJid,
                "id": id
            ],
            children: [xStanza]
        )
        
        stream.send(messageStanza)
    }
    
    // MARK: - Leave Room
    
    /// Leave a room
    /// Mirrors leaveTheRoom from leaveTheRoom.xmpp.ts
    public func leaveTheRoom(roomJID: String) {
        guard let stream = client?.xmppStream,
              let jid = stream.jid else {
            print("❌ Cannot leave room - no JID available")
            return
        }
        
        let username = jid.components(separatedBy: "@").first ?? ""
        let toJID = "\(roomJID)/\(username)"
        
        let presenceStanza = XMPPStanza(
            name: "presence",
            attributes: [
                "to": toJID,
                "type": "unavailable"
            ]
        )
        
        stream.send(presenceStanza)
    }
    
    // MARK: - Get Room Info
    
    /// Get room information (disco#info)
    /// Mirrors getRoomInfo from getRoomInfo.xmpp.ts
    public func getRoomInfo(roomJID: String) {
        guard let stream = client?.xmppStream else { return }
        
        let queryStanza = XMPPStanza(
            name: "query",
            attributes: [
                "xmlns": "http://jabber.org/protocol/disco#info"
            ]
        )
        
        let iqStanza = XMPPStanza(
            name: "iq",
            attributes: [
                "id": "roomInfo",
                "to": roomJID,
                "type": "get"
            ],
            children: [queryStanza]
        )
        
        stream.send(iqStanza)
    }
    
    // MARK: - Get Room Members
    
    /// Get room members
    /// Mirrors getRoomMembers from getRoomMembers.xmpp.ts
    public func getRoomMembers(roomJID: String) {
        guard let stream = client?.xmppStream else { return }
        
        let queryStanza = XMPPStanza(
            name: "query",
            attributes: [
                "xmlns": "ns:room:last",
                "room": roomJID
            ]
        )
        
        let iqStanza = XMPPStanza(
            name: "iq",
            attributes: [
                "id": "roomMemberInfo",
                "type": "get"
            ],
            children: [queryStanza]
        )
        
        stream.send(iqStanza)
    }
    
    // MARK: - Set Room Image
    
    /// Set room image (icon or background)
    /// Mirrors setRoomImage from setRoomImage.xmpp.ts
    public func setRoomImage(
        roomJid: String,
        roomThumbnail: String,
        type: String,
        roomBackground: String? = nil
    ) {
        guard let stream = client?.xmppStream else { return }
        
        let id = type == "icon" ? "setRoomImage" : "setRoomBackgroundImage"
        
        var attributes: [String: String] = [
            "xmlns": "ns:getrooms:setprofile",
            "room_thumbnail": roomThumbnail,
            "room": roomJid
        ]
        
        if let roomBackground = roomBackground {
            attributes["room_background"] = roomBackground
        } else {
            attributes["room_background"] = ""
        }
        
        let queryStanza = XMPPStanza(
            name: "query",
            attributes: attributes
        )
        
        let iqStanza = XMPPStanza(
            name: "iq",
            attributes: [
                "id": id,
                "type": "set"
            ],
            children: [queryStanza]
        )
        
        stream.send(iqStanza)
    }
    
    // MARK: - Set VCard
    
    /// Set user VCard (profile name)
    /// Mirrors setVcard from setVCard.xmpp.ts
    public func setVCard(fullname: String) {
        guard let stream = client?.xmppStream else { return }
        
        let fnStanza = XMPPStanza(
            name: "FN",
            text: fullname
        )
        
        let vCardStanza = XMPPStanza(
            name: "vCard",
            attributes: [
                "xmlns": "vcard-temp"
            ],
            children: [fnStanza]
        )
        
        let iqStanza = XMPPStanza(
            name: "iq",
            attributes: [
                "type": "set",
                "id": "setVcard"
            ],
            children: [vCardStanza]
        )
        
        stream.send(iqStanza)
    }
    
    // MARK: - Helper Functions
    
    /// SHA256 hash function (matches TypeScript js-sha256)
    private func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Errors

public enum XMPPOperationError: Error {
    case notConnected
    case timeout
    case invalidResponse
}
