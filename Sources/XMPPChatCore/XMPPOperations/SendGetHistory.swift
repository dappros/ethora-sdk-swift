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
            // Post notification for error handling
            NotificationCenter.default.post(
                name: NSNotification.Name("XMPPHistoryLoadFailed"),
                object: nil,
                userInfo: ["error": "Not connected", "roomJID": chatJID]
            )
            return
        }
        
        guard let client = client else {
            print("❌ Cannot send get-history: client is nil")
            NotificationCenter.default.post(
                name: NSNotification.Name("XMPPHistoryLoadFailed"),
                object: nil,
                userInfo: ["error": "Client is nil", "roomJID": chatJID]
            )
            return
        }
        
        // Validate 'before' parameter - must be a valid timestamp
        // Timestamps should be between year 2000 and year 2100 in milliseconds
        let validBefore: Int64? = {
            guard let before = before else { return nil }
            
            // Valid timestamp range (milliseconds since 1970)
            let minTimestamp: Int64 = 946684800000  // Jan 1, 2000
            let maxTimestamp: Int64 = 4102444800000 // Jan 1, 2100
            
            if before > minTimestamp && before < maxTimestamp {
                print("✅ Valid 'before' timestamp: \(before)")
                return before
            }
            
            // If it looks like seconds instead of milliseconds, convert
            if before > 946684800 && before < 4102444800 {
                let converted = before * 1000
                print("⚠️ Converted 'before' from seconds to milliseconds: \(before) -> \(converted)")
                return converted
            }
            
            print("⚠️ Invalid 'before' timestamp: \(before), sending empty <before/> to get latest messages")
            return nil
        }()
        
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
        if let validBefore = validBefore {
            beforeStanza = XMPPStanza(name: "before", text: "\(validBefore)")
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
        print("   Before (original): \(before?.description ?? "nil")")
        print("   Before (validated): \(validBefore?.description ?? "nil (getting latest)")")
        print("   Query ID: \(id)")
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

