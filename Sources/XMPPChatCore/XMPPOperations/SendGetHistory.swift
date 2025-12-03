//
//  SendGetHistory.swift
//  XMPPChatCore
//
//  Sends get-history MAM query without collecting responses
//  Messages will be handled by StanzaHandlers.onMessageHistory
//  Translated from getHistory.xmpp.ts (simplified - only sends query)
//

import Foundation

extension XMPPOperations {
    /// Send get-history MAM query
    /// Messages will be handled automatically by StanzaHandlers.onMessageHistory
    /// - Parameters:
    ///   - chatJID: Room JID (e.g., "room@conference.example.com")
    ///   - max: Maximum number of messages to retrieve
    ///   - before: Optional message ID (Int64) to get messages before this message (matching TypeScript: Number(firstMessageId))
    ///   - otherId: Optional custom ID for the request
    public func sendGetHistory(
        chatJID: String,
        max: Int,
        before: Int64? = nil,
        otherId: String? = nil
    ) {
        guard let stream = client?.xmppStream else {
            print("❌ Cannot send get-history: not connected")
            return
        }
        
        guard let client = client else {
            print("❌ Cannot send get-history: client is nil")
            return
        }
        
        // Match TypeScript: const fixedChatJid = chatJID.includes('@') ? chatJID : `${chatJID}@conference.dev.xmpp.ethoradev.com`;
        let conferenceDomain = client.conference
        let fixedChatJid = chatJID.contains("@") 
            ? chatJID 
            : "\(chatJID)@\(conferenceDomain)"
        
        // Match TypeScript: const id = otherId ?? `get-history:${Date.now().toString()}`;
        let id = otherId ?? "get-history:\(Int64(Date().timeIntervalSince1970 * 1000))"
        
        // Build MAM query stanza - Match TypeScript exactly
        // xml('max', {}, max.toString())
        let maxStanza = XMPPStanza(name: "max", text: "\(max)")
        
        // before ? xml('before', {}, before.toString()) : xml('before')
        // Matching TypeScript: before is message ID converted to number (Number(firstMessageId))
        let beforeStanza: XMPPStanza
        if let before = before {
            beforeStanza = XMPPStanza(name: "before", text: "\(before)")
        } else {
            beforeStanza = XMPPStanza(name: "before")
        }
        
        // xml('set', { xmlns: 'http://jabber.org/protocol/rsm' }, ...)
        let setStanza = XMPPStanza(
            name: "set",
            attributes: ["xmlns": "http://jabber.org/protocol/rsm"],
            children: [maxStanza, beforeStanza]
        )
        
        // xml('query', { xmlns: 'urn:xmpp:mam:2' }, ...)
        let queryStanza = XMPPStanza(
            name: "query",
            attributes: ["xmlns": "urn:xmpp:mam:2"],
            children: [setStanza]
        )
        
        // xml('iq', { type: 'set', to: fixedChatJid, id: id }, ...)
        let iqStanza = XMPPStanza(
            name: "iq",
            attributes: [
                "type": "set",
                "to": fixedChatJid,
                "id": id
            ],
            children: [queryStanza]
        )
        
        // Log the query being sent
        let queryXML = iqStanza.toXML()
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📤 SENDING GET-HISTORY MAM QUERY:")
        print("   Room: \(fixedChatJid)")
        print("   Max: \(max)")
        print("   Before: \(before?.description ?? "nil")")
        print("   ID: \(id)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📄 XML STRING THAT WILL BE SENT:")
        print(queryXML)
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        // Match TypeScript: client?.send(message).catch((err) => console.log('err on load', err));
        stream.send(iqStanza)
        
        print("✅ Get-history query sent. Messages will be handled by StanzaHandlers.onMessageHistory")
        print("⏳ Waiting for messages to arrive...")
    }
}

