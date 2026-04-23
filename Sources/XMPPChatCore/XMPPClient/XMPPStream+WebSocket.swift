//
//  XMPPStream+WebSocket.swift
//  XMPPChatCore
//

import Foundation
import Starscream

extension XMPPStream_WebSocket: WebSocketDelegate {
    public func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        switch event {
        case .connected(let headers):
            // WebSocket connected - this triggers the XMPP protocol flow
            isConnected = true
            // NSlog("✅ WebSocket connected")
            // print("✅ WebSocket connected")
            
            // This is required by XMPP protocol - we need to initiate the XMPP stream
            sendInitialStreamHeader()
            
        case .disconnected(let reason, let code):
            // Detailed disconnect logging
            //NSlog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            //NSlog("⚠️ WEBSOCKET DISCONNECTED")
            //NSlog("   Code: %d", code)
            //NSlog("   Reason: %@", reason)
            //NSlog("   Code Meaning: %@", getDisconnectCodeMeaning(code))
            //NSlog("   Was Connected: %@", isConnected ? "YES" : "NO")
            //NSlog("   Current JID: %@", jid ?? "nil")
            //NSlog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            //print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            //print("⚠️ WEBSOCKET DISCONNECTED")
            //print("   Disconnect Code: \(code)")
            //print("   Reason: \(reason)")
            //print("   Code Meaning: \(getDisconnectCodeMeaning(code))")
            //print("   Was Connected: \(isConnected ? "YES" : "NO")")
            //print("   Current JID: \(jid ?? "nil")")
            
            isConnected = false
            let disconnectError = NSError(
                domain: "XMPPStream",
                code: Int(code),
                userInfo: [
                    NSLocalizedDescriptionKey: reason,
                    "disconnectCode": code,
                    "reason": reason
                ]
            )
            
            delegate?.xmppStreamDidDisconnect(self, error: disconnectError)
            
        case .text(let string):
            // Raw WebSocket trace — every byte received from server, for wire-level
            // diagnostics of the XMPP handshake (open/features/SASL/bind/session).
            print("📥 WS IN: \(string)")
            
            // First handle at stream level (auth flow, features, etc.)
            handleServerResponse(string)
            
            // Then parse and handle as stanza
            // Only parse if it's not a stream-level element (open, close, features, etc.)
            // These are handled in handleServerResponse above
            if !string.contains("<open") && 
               !string.contains("<close") && 
               !string.contains("<stream:features") && 
               !string.contains("<stream:error") &&
               !string.contains("<success xmlns='urn:ietf:params:xml:ns:xmpp-sasl'") {
                
                if let stanza = parseStanza(string) {
                    // //NSlog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    // //NSlog("📦 PROCESSED STANZA: %@", stanza.name)
                    // //NSlog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    //print("📦 PROCESSED STANZA: \(stanza.name)")
                    
                    // In XMPP, after authentication, we receive a stream response or presence
                    // Check for successful authentication indicators
                    if !isConnected || jid == nil {
                        // Check if this is a stream response indicating successful auth
                        if stanza.name == "stream:stream" || 
                           stanza.name == "open" ||
                           (stanza.name == "iq" && stanza.attributes["type"] == "result") {
                            // Auth might be complete
                        }
                        
                        // If it's presence from ourselves, we're definitely online
                        if stanza.name == "presence", let from = stanza.attributes["from"] {
                            if jid == nil || from.contains(jid!) || jid!.contains(from) {
                                // //NSlog("✅ Presence received from self - Online!")
                                //print("✅ Presence received from self - Online!")
                                //print("JID: \(from)")
                                delegate?.xmppStreamDidBecomeOnline(self, jid: from)
                            }
                        } else if stanza.name == "iq" && 
                                  stanza.attributes["type"] == "result" &&
                                  (stanza.attributes["id"]?.contains("bind") == true || 
                                   stanza.attributes["id"]?.contains("session") == true) {
                            // Bind or Session result also indicates we're getting online
                            // This is handled in handleServerResponse but we can double check here
                        } else if stanza.name == "stream:features" {
                            // Stream features received - authentication can proceed
                            // This is handled automatically by the XMPP protocol
                        }
                    }
                    
                    // Send stanza to delegate (XMPPClient) which routes through HandleStanzas
                    // This ensures all stanzas go through the proper handler chain (HandleStanzas -> StanzaHandlers)
                    delegate?.xmppStream(self, didReceiveStanza: stanza)
                } else {
                    //NSlog("⚠️⚠️⚠️ FAILED TO PARSE STANZA ⚠️⚠️⚠️")
                    //NSlog("   Raw XML: %@", string)
                    //print("⚠️⚠️⚠️ FAILED TO PARSE STANZA ⚠️⚠️⚠️")
                    //print("   Raw XML: \(string)")
                }
            } else {
                //NSlog("ℹ️ Stream-level element, not parsing as stanza")
                //print("ℹ️ Stream-level element, not parsing as stanza")
            }
            
        case .error(let wsError):
            isConnected = false
            delegate?.xmppStreamDidDisconnect(self, error: wsError)
            if let wsErr = wsError {
                delegate?.xmppStream(self, didReceiveError: wsErr)
            }
            
        case .binary(let data):
            // Handle binary data if needed
            break
            
        default:
            break
        }
    }
}
