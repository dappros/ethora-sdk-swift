//
//  XMPPStream+Handlers.swift
//  XMPPChatCore
//

import Foundation

extension XMPPStream_WebSocket {
    // MARK: - Server Response Handling
    
    // Handle server responses and implement XMPP authentication flow
    internal func handleServerResponse(_ xmlString: String) {
        // Check for server's open response (RFC 7395)
        if xmlString.contains("<open") && xmlString.contains("urn:ietf:params:xml:ns:xmpp-websocket") {
            //NSlog("📥 Received server <open> response")
            //print("📥 Received server <open> response")
            
            // Extract stream ID if present
            if let idRange = xmlString.range(of: "id='([^']+)'", options: .regularExpression) {
                let streamId = String(xmlString[idRange]).replacingOccurrences(of: "id='", with: "").replacingOccurrences(of: "'", with: "")
                if !streamId.isEmpty {
                    // //NSlog("   Stream ID: %@", streamId)
                    //print("   Stream ID: \(streamId)")
                }
            }
            return
        }
        
        // Check for server's stream:stream response (alternative format)
        if xmlString.contains("<stream:stream") {
            //NSlog("📥 Received server stream:stream header")
            //print("📥 Received server stream:stream header")
            
            // Extract stream ID if present
            if let idRange = xmlString.range(of: "id=['\"]([^'\"]+)['\"]", options: .regularExpression) {
                let streamId = String(xmlString[idRange]).replacingOccurrences(of: "id=", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                if !streamId.isEmpty {
                    // //NSlog("   Stream ID: %@", streamId)
                    //print("   Stream ID: \(streamId)")
                }
            }
            return
        }
        
        // Check for stream:features (can be standalone or inside stream:stream/open)
        // RFC 7395: Features come after <open> response
        if xmlString.contains("<stream:features") || xmlString.contains("<features") || xmlString.contains("xmlns=\"http://etherx.jabber.org/streams\"") || xmlString.contains("xmlns='http://etherx.jabber.org/streams'") {
            //NSlog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            //NSlog("📥 STEP 2: RECEIVED STREAM FEATURES")
            //NSlog("   Auth State: %@", String(describing: authState))
            //NSlog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            //print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            //print("📥 STEP 2: RECEIVED STREAM FEATURES")
            //print("   Auth State: \(authState)")
            
            if authState == .notStarted || authState == .saslAuthSent {
                // Always try SASL PLAIN - it's standard
                //NSlog("   Sending SASL PLAIN authentication...")
                //print("   Sending SASL PLAIN authentication...")
                sendSASLAuth()
            } else if authState == .saslSuccess {
                // After SASL success, we receive stream features again - need to bind
                //NSlog("   After SASL success - sending bind...")
                //print("   After SASL success - sending bind...")
                sendResourceBind()
            }
            return
        }
        
        // Check for SASL success (can be just <success/> or with xmlns)
        if xmlString.contains("<success") || (xmlString.contains("success") && xmlString.contains("urn:ietf:params:xml:ns:xmpp-sasl")) {
            //NSlog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            //NSlog("✅ STEP 3: SASL AUTHENTICATION SUCCESS")
            //NSlog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            //print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            //print("✅ STEP 3: SASL AUTHENTICATION SUCCESS")
            
            authState = .saslSuccess
            
            // After SASL success, RFC 6120 requires restarting the stream
            //NSlog("   Restarting stream after SASL success...")
            //print("   Restarting stream after SASL success...")
            // Don't reset authState yet - keep it as .saslSuccess so we know we're in post-SASL flow
            sendInitialStreamHeader()
            return
        }
        
        // Check for SASL failure
        if xmlString.contains("<failure") || (xmlString.contains("failure") && xmlString.contains("urn:ietf:params:xml:ns:xmpp-sasl")) {
            //NSlog("❌ STEP 3: SASL AUTHENTICATION FAILED")
            //print("❌ STEP 3: SASL AUTHENTICATION FAILED")
            authState = .notStarted
            let error = NSError(domain: "XMPPStream", code: 401, userInfo: [NSLocalizedDescriptionKey: "SASL Authentication Failed"])
            delegate?.xmppStream(self, didReceiveError: error)
            return
        }
        
        // Check for bind result
        let hasBindResultType = xmlString.contains("type='result'") || xmlString.contains("type=\"result\"")
        let hasBind = xmlString.contains("bind") || xmlString.contains("urn:ietf:params:xml:ns:xmpp-bind")
        let hasBindId = xmlString.contains("bind-") // Our bind IQ has id starting with "bind-"
        
        if hasBindResultType && (hasBind || hasBindId) {
            //NSlog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            //NSlog("✅ STEP 4: RESOURCE BOUND SUCCESS")
            //NSlog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            //print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            //print("✅ STEP 4: RESOURCE BOUND SUCCESS")
            //print("   Full XML: \(xmlString)")
            
            // Extract JID from bind result - try multiple patterns
            var extractedJID: String? = nil
            
            // Pattern 1: <jid>...</jid>
            if let jidMatch = xmlString.range(of: "<jid>([^<]+)</jid>", options: .regularExpression) {
                let jidString = String(xmlString[jidMatch])
                // Extract content between > and <
                if let start = jidString.firstIndex(of: ">"), let end = jidString.lastIndex(of: "<") {
                    let contentStart = jidString.index(after: start)
                    if contentStart < end {
                        extractedJID = String(jidString[contentStart..<end])
                    }
                }
            }
            
            if let jid = extractedJID {
                self.jid = jid
                //NSlog("   Bound JID: %@", jid)
                //print("   Bound JID: \(jid)")
            } else {
                // Fallback: construct JID from username and host
                if let username = username, let host = url.host {
                    let fallbackJID = "\(username)@\(host)/\(resource)"
                    self.jid = fallbackJID
                    //NSlog("   Warning: Could not extract JID from bind result, using fallback: %@", fallbackJID)
                    //print("   Warning: Could not extract JID from bind result, using fallback: \(fallbackJID)")
                }
            }
            
            // Update state before sending session
            authState = .bindSent
            sendSessionEstablishment()
            // Note: authState will be updated to .sessionSent in sendSessionEstablishment
            return
        }
        
        // Check for session result (optional in XMPP 1.0, but some servers require it)
        // Session result can be identified by:
        // 1. Contains "session" or "urn:ietf:params:xml:ns:xmpp-session" in the XML
        // 2. OR if we're in sessionSent state and get a result type IQ with session ID
        let hasSessionResultType = xmlString.contains("type='result'") || xmlString.contains("type=\"result\"")
        let hasSessionContent = xmlString.contains("session") || xmlString.contains("urn:ietf:params:xml:ns:xmpp-session")
        let hasSessionId = xmlString.contains("id='session-") || xmlString.contains("id=\"session-")
        
        // If we're in sessionSent state and get a result with session ID, that's our session result
        if hasSessionResultType && (hasSessionContent || (hasSessionId && authState == .sessionSent)) {
            //NSlog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            //NSlog("✅ STEP 5: SESSION ESTABLISHED - XMPP ONLINE!")
            //NSlog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            //print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            //print("✅ STEP 5: SESSION ESTABLISHED - XMPP ONLINE!")
            
            authState = .authenticated
            if let jid = jid {
                delegate?.xmppStreamDidBecomeOnline(self, jid: jid)
            } else if let username = username, let host = url.host {
                let fallbackJID = "\(username)@\(host)/\(resource)"
                delegate?.xmppStreamDidBecomeOnline(self, jid: fallbackJID)
            }
            return
        }
        
        // Check for stream:error with conflict (connection replaced)
        if xmlString.contains("<stream:error") && xmlString.contains("conflict") {
            if xmlString.contains("Replaced by new connection") {
                //NSlog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                //NSlog("⚠️ ERROR: CONNECTION CONFLICT")
                //NSlog("   Reason: Replaced by new connection")
                //NSlog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                //print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                //print("⚠️ ERROR: CONNECTION CONFLICT")
                //print("   Another connection is active. This connection will close.")
                
                let replacedError = NSError(
                    domain: "XMPPStream",
                    code: 409,
                    userInfo: [NSLocalizedDescriptionKey: "Connection replaced by new session. Do not reconnect."]
                )
                
                //print("   Do NOT reconnect - the other connection is handling it.")
                
                // Notify delegate (will stop reconnection in XMPPClient)
                delegate?.xmppStreamDidDisconnect(self, error: replacedError)
                
                // Close the connection immediately
                socket?.disconnect()
                return
            }
        }
        
        // If we get here and we're authenticated, it's a normal stanza
        if authState == .authenticated {
            // Normal stanza processing happens in parseStanza below
            return
        }
        
        // Log unhandled response
        //NSlog("⚠️ Unhandled server response in state %@: %@", String(describing: authState), xmlString)
        //print("⚠️ Unhandled server response in state \(authState): \(xmlString)")
    }
}
