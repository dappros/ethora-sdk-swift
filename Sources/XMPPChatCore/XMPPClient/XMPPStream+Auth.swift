//
//  XMPPStream+Auth.swift
//  XMPPChatCore
//

import Foundation

extension XMPPStream_WebSocket {
    // MARK: - Authentication Methods
    
    // RFC 7395: XMPP over WebSocket uses <open> element, not <stream:stream>
    // However, @xmpp/client might use stream:stream format - let's try both approaches
    internal func sendInitialStreamHeader() {
        guard let host = url.host else {
            //NSlog("❌ Cannot send stream header - missing host or username")
            return
        }
        
        let openHeader = """
        <open xmlns='urn:ietf:params:xml:ns:xmpp-websocket' 
              to='\(host)' 
              version='1.0'/>
        """
        
        //NSlog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        //NSlog("📤 STEP 1: SENDING XMPP OPEN (RFC 7395)")
        //NSlog("   To: %@", host)
        //NSlog("   Header Length: %lu bytes", openHeader.count)
        //NSlog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        //print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        //print("📤 STEP 1: SENDING XMPP OPEN (RFC 7395)")
        //print("   To: \(host)")
        
        // Write to socket
        socket?.write(string: openHeader)
    }

    // Send SASL authentication
    internal func sendSASLAuth() {
        guard let username = username, let password = password else {
            //NSlog("❌ Cannot send SASL auth - missing username or password")
            return
        }
        
        // Format: \0username\0password
        let authString = "\0\(username)\0\(password)"
        guard let authData = authString.data(using: .utf8) else { return }
        let base64Auth = authData.base64EncodedString()
        
        let saslAuth = "<auth xmlns='urn:ietf:params:xml:ns:xmpp-sasl' mechanism='PLAIN'>\(base64Auth)</auth>"
        
        //NSlog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        //NSlog("📤 STEP 2: SENDING SASL AUTH")
        //NSlog("   Mechanism: PLAIN")
        //NSlog("   Username: %@", username)
        //NSlog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        //print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        //print("📤 STEP 2: SENDING SASL AUTH")
        //print("   Mechanism: PLAIN")
        //print("   Username: \(username)")
        
        authState = .saslAuthSent
        socket?.write(string: saslAuth)
    }
    
    // Send resource bind request
    internal func sendResourceBind() {
        let bindId = "bind-\(UUID().uuidString)"
        let bindIQ = "<iq type='set' id='\(bindId)'><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'><resource>\(resource)</resource></bind></iq>"
        
        //NSlog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        //NSlog("📤 STEP 4: SENDING RESOURCE BIND")
        //NSlog("   Resource: %@", resource)
        //NSlog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        //print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        //print("📤 STEP 4: SENDING RESOURCE BIND")
        //print("   Resource: \(resource)")
        
        authState = .bindSent
        socket?.write(string: bindIQ)
    }
    
    // Send session establishment
    internal func sendSessionEstablishment() {
        let sessionId = "session-\(UUID().uuidString)"
        let sessionIQ = "<iq type=\"set\" id=\"\(sessionId)\"><session xmlns=\"urn:ietf:params:xml:ns:xmpp-session\"/></iq>"
        
        //NSlog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        //NSlog("📤 STEP 5: SENDING SESSION ESTABLISHMENT")
        //NSlog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        //print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        //print("📤 STEP 5: SENDING SESSION ESTABLISHMENT")
        
        authState = .sessionSent
        socket?.write(string: sessionIQ)
    }
}
