//
//  XMPPStream.swift
//  XMPPChatCore
//
//  XMPP Stream implementation
//  Uses XMPPFramework if available, otherwise falls back to WebSocket implementation
//

import Foundation
import Starscream
import os.log

public protocol XMPPStreamDelegate: AnyObject {
    func xmppStreamDidConnect(_ stream: XMPPStream)
    func xmppStreamDidBecomeOnline(_ stream: XMPPStream, jid: String)
    func xmppStreamDidDisconnect(_ stream: XMPPStream, error: Error?)
    func xmppStream(_ stream: XMPPStream, didReceiveStanza stanza: XMPPStanza)
    func xmppStream(_ stream: XMPPStream, didSendStanza stanza: XMPPStanza)
    func xmppStream(_ stream: XMPPStream, didReceiveError error: Error)
}

// MARK: - WebSocket-based Implementation (Fallback)
public class XMPPStream_WebSocket {
    private var socket: WebSocket?
    private var url: URL
    public private(set) var jid: String?
    private var isConnected: Bool = false
    private var stanzaHandlers: [(XMPPStanza) -> Void] = []
    // Priority handlers run first and can stop propagation
    private var priorityStanzaHandlers: [(XMPPStanza) -> Bool] = [] // Returns true if handled (should stop propagation)
    
    // Store credentials for authentication
    private var username: String?
    private var password: String?
    private var resource: String = "default"
    
    public weak var delegate: XMPPStreamDelegate?
    
    public init(service: String) {
        guard let url = URL(string: service) else {
            fatalError("Invalid XMPP service URL: \(service)")
        }
        self.url = url
    }
    
    public func connect(username: String, password: String, resource: String = "default") {
        var request = URLRequest(url: url)
        // Increase timeout to prevent connection timeouts
        request.timeoutInterval = 30.0
        
        // Add WebSocket subprotocol if needed
        request.setValue("xmpp", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        
        socket = WebSocket(request: request)
        socket?.delegate = self
        
        // Store credentials for later use in authentication
        self.username = username
        self.password = password
        self.resource = resource
        
        self.jid = "\(username)@\(url.host ?? "")/\(resource)"
        
        // Match TypeScript: this.client.start().catch((error) => { console.error('Error starting client:', error); });
        socket?.connect()
    }
    
    public func disconnect() {
        socket?.disconnect()
        socket = nil
        isConnected = false
    }
    
    public func send(_ stanza: XMPPStanza) {
        let xml = stanza.toXML()
        
        guard let socket = socket else {
            return
        }
        
        socket.write(string: xml)
        delegate?.xmppStream(self, didSendStanza: stanza)
    }
    
    public func send(_ xml: String) {
        guard let socket = socket else {
            return
        }
        
        socket.write(string: xml)
    }
    
    public func on(_ event: String, handler: @escaping (XMPPStanza) -> Void) {
        // Simplified event handling
        stanzaHandlers.append(handler)
    }
    
    public func on(_ event: String, priority: Bool = false, handler: @escaping (XMPPStanza) -> Bool) {
        // Priority handlers run first and can stop propagation by returning true
        if priority {
            priorityStanzaHandlers.append(handler)
        } else {
            // Convert to non-priority handler
            stanzaHandlers.append { stanza in
                _ = handler(stanza)
            }
        }
    }
    
    public func off(_ event: String, handler: @escaping (XMPPStanza) -> Void) {
        // Remove handler - simplified
        if let index = stanzaHandlers.firstIndex(where: { $0 as AnyObject === handler as AnyObject }) {
            stanzaHandlers.remove(at: index)
        }
    }
    
    public func off(_ event: String, priorityHandler: @escaping (XMPPStanza) -> Bool) {
        // Remove priority handler
        if let index = priorityStanzaHandlers.firstIndex(where: { $0 as AnyObject === priorityHandler as AnyObject }) {
            priorityStanzaHandlers.remove(at: index)
        }
    }
    
    private func parseStanza(_ xmlString: String) -> XMPPStanza? {
        // Simplified XML parsing - in production, use XMLParser or a proper XML library
        // This is a placeholder implementation
        return XMPPStanzaParser.parse(xmlString)
    }
    
    // Track authentication state
    private var authState: AuthState = .notStarted
    private var streamId: String?
    
    enum AuthState {
        case notStarted
        case streamHeaderSent
        case streamFeaturesReceived
        case saslAuthSent
        case saslSuccess
        case bindSent
        case sessionSent
        case authenticated
    }
    
    // Match TypeScript: Send initial XMPP stream header after WebSocket connects
    // RFC 7395: XMPP over WebSocket uses <open> element, not <stream:stream>
    // However, @xmpp/client might use stream:stream format - let's try both approaches
    private func sendInitialStreamHeader() {
        guard let host = url.host, let username = username else {
            NSLog("❌ Cannot send stream header - missing host or username")
            print("❌ Cannot send stream header - missing host or username")
            return
        }
        
        // Try RFC 7395 format first: <open> element for WebSocket
        // Format: <open xmlns='urn:ietf:params:xml:ns:xmpp-framing' to='host' version='1.0'/>
        let openHeader = "<open xmlns='urn:ietf:params:xml:ns:xmpp-framing' to='\(host)' version='1.0'/>"
        
        NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        NSLog("📤 STEP 1: SENDING XMPP OPEN (RFC 7395)")
        NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        NSLog("   Host: %@", host)
        NSLog("   Username: %@", username)
        NSLog("   Open Header: %@", openHeader)
        NSLog("   Header Length: %lu bytes", openHeader.count)
        NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📤 STEP 1: SENDING XMPP OPEN (RFC 7395)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("   Host: \(host)")
        print("   Username: \(username)")
        print("   Open Header: \(openHeader)")
        print("   Header Length: \(openHeader.count) bytes")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        // Only set to streamHeaderSent if we're not already in post-SASL flow
        if authState != .saslSuccess {
            authState = .streamHeaderSent
        }
        
        // Write to socket
        socket?.write(string: openHeader) { [weak self] in
            NSLog("✅ Open header written to WebSocket")
            print("✅ Open header written to WebSocket")
        }
    }
    
    // Handle server responses and implement XMPP authentication flow
    private func handleServerResponse(_ xmlString: String) {
        // NSLog("🔍 Processing server response - Auth State: %@", String(describing: authState))
        // print("🔍 Processing server response - Auth State: \(authState)")
        
        // RFC 7395: Server responds with <open> or <stream:stream>
        // Check for server's <open> response
        if xmlString.contains("<open") && xmlString.contains("urn:ietf:params:xml:ns:xmpp-framing") {
            NSLog("📥 Received server <open> response")
            print("📥 Received server <open> response")
            
            // Extract stream ID if present
            if let idMatch = xmlString.range(of: "id=['\"]([^'\"]+)['\"]", options: .regularExpression) {
                let idString = String(xmlString[idMatch])
                if let idValue = idString.range(of: "['\"]([^'\"]+)['\"]", options: .regularExpression) {
                    streamId = String(idString[idValue])
                    NSLog("   Stream ID: %@", streamId ?? "none")
                    print("   Stream ID: \(streamId ?? "none")")
                }
            }
            return
        }
        
        // Check for server's stream:stream response (alternative format)
        if xmlString.contains("<stream:stream") {
            NSLog("📥 Received server stream:stream header")
            print("📥 Received server stream:stream header")
            
            // Extract stream ID if present
            if let idMatch = xmlString.range(of: "id=['\"]([^'\"]+)['\"]", options: .regularExpression) {
                let idString = String(xmlString[idMatch])
                if let idValue = idString.range(of: "['\"]([^'\"]+)['\"]", options: .regularExpression) {
                    streamId = String(idString[idValue])
                    NSLog("   Stream ID: %@", streamId ?? "none")
                    print("   Stream ID: \(streamId ?? "none")")
                }
            }
            return
        }
        
        // Check for stream:features (can be standalone or inside stream:stream/open)
        // RFC 7395: Features come after <open> response
        if xmlString.contains("<stream:features") || xmlString.contains("<features") || xmlString.contains("xmlns=\"http://etherx.jabber.org/streams\"") || xmlString.contains("xmlns='http://etherx.jabber.org/streams'") {
            NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            NSLog("📥 STEP 2: RECEIVED STREAM FEATURES")
            NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            NSLog("   Full XML: %@", xmlString)
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("📥 STEP 2: RECEIVED STREAM FEATURES")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("   Full XML: \(xmlString)")
            
            if authState == .streamHeaderSent {
                authState = .streamFeaturesReceived
                // Always try SASL PLAIN - it's standard
                NSLog("   Sending SASL PLAIN authentication...")
                print("   Sending SASL PLAIN authentication...")
                sendSASLAuth()
            } else if authState == .saslSuccess {
                // After SASL success, we receive stream features again - need to bind
                NSLog("   After SASL success - sending bind...")
                print("   After SASL success - sending bind...")
                sendResourceBind()
            }
            return
        }
        
        // Check for SASL success (can be just <success/> or with xmlns)
        if xmlString.contains("<success") || (xmlString.contains("success") && xmlString.contains("urn:ietf:params:xml:ns:xmpp-sasl")) {
            NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            NSLog("✅ STEP 3: SASL AUTHENTICATION SUCCESS")
            NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("✅ STEP 3: SASL AUTHENTICATION SUCCESS")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            
            authState = .saslSuccess
            // After SASL success, send new <open> to restart stream (RFC 7395)
            // Reset to streamHeaderSent so we can process the new features correctly
            NSLog("   Restarting stream after SASL success...")
            print("   Restarting stream after SASL success...")
            // Don't reset authState yet - keep it as .saslSuccess so we know we're in post-SASL flow
            sendInitialStreamHeader()
            return
        }
        
        // Check for SASL failure
        if xmlString.contains("<failure") || (xmlString.contains("failure") && xmlString.contains("urn:ietf:params:xml:ns:xmpp-sasl")) {
            NSLog("❌❌❌ SASL AUTHENTICATION FAILED ❌❌❌")
            NSLog("   Response: %@", xmlString)
            print("❌❌❌ SASL AUTHENTICATION FAILED ❌❌❌")
            print("   Response: \(xmlString)")
            return
        }
        
        // Check for bind result - handle both 'type="result"' and 'type='result''
        let hasBindResultType = xmlString.contains("type=\"result\"") || xmlString.contains("type='result'")
        let hasBind = xmlString.contains("bind") || xmlString.contains("urn:ietf:params:xml:ns:xmpp-bind")
        let hasBindId = xmlString.contains("bind-") // Our bind IQ has id starting with "bind-"
        
        if hasBindResultType && (hasBind || hasBindId) {
            NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            NSLog("✅ STEP 4: BIND SUCCESS")
            NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            NSLog("   Full XML: %@", xmlString)
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("✅ STEP 4: BIND SUCCESS")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("   Full XML: \(xmlString)")
            
            // Extract JID from bind result - try multiple patterns
            var extractedJID: String? = nil
            
            // Pattern 1: <jid>...</jid>
            if let jidMatch = xmlString.range(of: "<jid>([^<]+)</jid>", options: .regularExpression) {
                let jidString = String(xmlString[jidMatch])
                // Extract content between > and <
                if let startRange = jidString.range(of: ">"), let endRange = jidString.range(of: "<", range: startRange.upperBound..<jidString.endIndex) {
                    extractedJID = String(jidString[startRange.upperBound..<endRange.lowerBound])
                }
            }
            
            // Pattern 2: <jid>...</jid> with namespace
            if extractedJID == nil, let jidMatch = xmlString.range(of: "<bind[^>]*><jid>([^<]+)</jid>", options: .regularExpression) {
                let jidString = String(xmlString[jidMatch])
                if let jidValue = jidString.range(of: "<jid>([^<]+)</jid>", options: .regularExpression) {
                    let fullMatch = String(xmlString[jidValue])
                    if let innerMatch = fullMatch.range(of: ">([^<]+)<", options: .regularExpression) {
                        extractedJID = String(fullMatch[innerMatch])
                    }
                }
            }
            
            if let jid = extractedJID {
                self.jid = jid
                NSLog("   Bound JID: %@", jid)
                print("   Bound JID: \(jid)")
            } else {
                // Fallback: construct JID from username and host
                if let username = username, let host = url.host {
                    let fallbackJID = "\(username)@\(host)/\(resource)"
                    self.jid = fallbackJID
                    NSLog("   Using constructed JID: %@", fallbackJID)
                    print("   Using constructed JID: \(fallbackJID)")
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
        // 2. Has type="result" and id starting with "session-" (our session IQ ID pattern)
        let hasSessionResultType = xmlString.contains("type=\"result\"") || xmlString.contains("type='result'")
        let hasSessionContent = xmlString.contains("session") || xmlString.contains("urn:ietf:params:xml:ns:xmpp-session")
        let hasSessionId = xmlString.contains("id='session-") || xmlString.contains("id=\"session-")
        
        // If we're in sessionSent state and get a result with session ID, that's our session result
        if hasSessionResultType && (hasSessionContent || (hasSessionId && authState == .sessionSent)) {
            NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            NSLog("✅ STEP 5: SESSION ESTABLISHED - XMPP ONLINE!")
            NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            NSLog("   Full XML: %@", xmlString)
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("✅ STEP 5: SESSION ESTABLISHED - XMPP ONLINE!")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("   Full XML: \(xmlString)")
            
            authState = .authenticated
            // Use bound JID or constructed JID
            if let boundJID = jid {
                delegate?.xmppStreamDidBecomeOnline(self, jid: boundJID)
            } else if let username = username, let host = url.host {
                let fallbackJID = "\(username)@\(host)/\(resource)"
                delegate?.xmppStreamDidBecomeOnline(self, jid: fallbackJID)
            }
            return
        }
        
        // Check for stream:error with conflict (connection replaced)
        if xmlString.contains("<stream:error") && xmlString.contains("conflict") {
            if xmlString.contains("Replaced by new connection") {
                NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                NSLog("⚠️⚠️⚠️ CONNECTION REPLACED BY NEW CONNECTION ⚠️⚠️⚠️")
                NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                NSLog("   Another connection is active. This connection will close.")
                NSLog("   Do NOT reconnect - the other connection is handling it.")
                NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("⚠️⚠️⚠️ CONNECTION REPLACED BY NEW CONNECTION ⚠️⚠️⚠️")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("   Another connection is active. This connection will close.")
                print("   Do NOT reconnect - the other connection is handling it.")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                
                // Notify delegate that connection was replaced
                if let delegate = delegate as? XMPPClient {
                    // Set flag to prevent reconnection
                    // We need to access XMPPClient's connectionReplaced flag
                    // This is a bit of a hack, but we need to prevent reconnection
                }
                return
            }
        }
        
        // If we get here and we're authenticated, it's a normal stanza
        if authState == .authenticated {
            // Normal stanza processing happens in parseStanza below
            return
        }
        
        // Log unhandled response
        NSLog("⚠️ Unhandled server response in state %@: %@", String(describing: authState), xmlString)
        print("⚠️ Unhandled server response in state \(authState): \(xmlString)")
    }
    
    // Send SASL authentication
    private func sendSASLAuth() {
        guard let username = username, let password = password else {
            NSLog("❌ Cannot send SASL auth - missing username or password")
            print("❌ Cannot send SASL auth - missing username or password")
            return
        }
        
        // SASL PLAIN format: base64(username\0username\0password)
        let authString = "\(username)\0\(username)\0\(password)"
        guard let authData = authString.data(using: .utf8) else {
            NSLog("❌ Failed to encode SASL auth string")
            print("❌ Failed to encode SASL auth string")
            return
        }
        let authBase64 = authData.base64EncodedString()
        
        let saslAuth = "<auth xmlns=\"urn:ietf:params:xml:ns:xmpp-sasl\" mechanism=\"PLAIN\">\(authBase64)</auth>"
        
        NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        NSLog("📤 STEP 3: SENDING SASL AUTHENTICATION")
        NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        NSLog("   Mechanism: PLAIN")
        NSLog("   Username: %@", username)
        NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📤 STEP 3: SENDING SASL AUTHENTICATION")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("   Mechanism: PLAIN")
        print("   Username: \(username)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        authState = .saslAuthSent
        socket?.write(string: saslAuth)
    }
    
    // Send resource bind request
    private func sendResourceBind() {
        guard let username = username else { return }
        
        let bindId = "bind-\(UUID().uuidString)"
        let bindIQ = "<iq type=\"set\" id=\"\(bindId)\"><bind xmlns=\"urn:ietf:params:xml:ns:xmpp-bind\"><resource>\(resource)</resource></bind></iq>"
        
        NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        NSLog("📤 STEP 4: SENDING RESOURCE BIND")
        NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📤 STEP 4: SENDING RESOURCE BIND")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        authState = .bindSent
        socket?.write(string: bindIQ)
    }
    
    // Send session establishment
    private func sendSessionEstablishment() {
        let sessionId = "session-\(UUID().uuidString)"
        let sessionIQ = "<iq type=\"set\" id=\"\(sessionId)\"><session xmlns=\"urn:ietf:params:xml:ns:xmpp-session\"/></iq>"
        
        NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        NSLog("📤 STEP 5: SENDING SESSION ESTABLISHMENT")
        NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📤 STEP 5: SENDING SESSION ESTABLISHMENT")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        authState = .sessionSent
        socket?.write(string: sessionIQ)
    }
    
    // Helper to get disconnect code meaning
    private func getDisconnectCodeMeaning(_ code: UInt16) -> String {
        switch code {
        case 1000:
            return "Normal closure (1000) - Connection closed normally"
        case 1001:
            return "Going away (1001) - Server is going down or client is navigating away"
        case 1002:
            return "Protocol error (1002) - Endpoint terminated connection due to protocol error"
        case 1003:
            return "Unacceptable data (1003) - Endpoint received unsupported data type"
        case 1005:
            return "No status received (1005) - No close code was provided"
        case 1006:
            return "Abnormal closure (1006) - Connection closed abnormally"
        case 1007:
            return "Invalid frame payload data (1007) - Invalid UTF-8 data received"
        case 1008:
            return "Policy violation (1008) - Message violates endpoint policy"
        case 1009:
            return "Message too big (1009) - Message is too large"
        case 1010:
            return "Missing extension (1010) - Server requires extension not supported by client"
        case 1011:
            return "Internal server error (1011) - Server encountered unexpected error"
        case 1015:
            return "TLS handshake failure (1015) - TLS handshake failed"
        default:
            return "Unknown code (\(code))"
        }
    }
}

// MARK: - Conditional Type Alias
// Use XMPPFramework if available, otherwise use WebSocket implementation
#if canImport(XMPPFramework)
// XMPPStream_XMPPFramework is defined in XMPPStream_XMPPFramework.swift
public typealias XMPPStream = XMPPStream_XMPPFramework
#else
// Use WebSocket implementation
public typealias XMPPStream = XMPPStream_WebSocket
#endif

extension XMPPStream_WebSocket: WebSocketDelegate {
    public func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        switch event {
        case .connected(let headers):
            // WebSocket connected - this triggers the XMPP protocol flow
            isConnected = true
            delegate?.xmppStreamDidConnect(self)
            
            // Match TypeScript: After WebSocket connects, send initial XMPP stream header
            // This is required by XMPP protocol - we need to initiate the XMPP stream
            sendInitialStreamHeader()
            
        case .disconnected(let reason, let code):
            // Detailed disconnect logging
            NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            NSLog("❌❌❌ WEBSOCKET DISCONNECTED ❌❌❌")
            NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            NSLog("   Disconnect Code: %u", code)
            NSLog("   Reason: %@", reason)
            NSLog("   Code Meaning: %@", getDisconnectCodeMeaning(code))
            NSLog("   Was Connected: %@", isConnected ? "YES" : "NO")
            NSLog("   Current JID: %@", jid ?? "nil")
            NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("❌❌❌ WEBSOCKET DISCONNECTED ❌❌❌")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("   Disconnect Code: \(code)")
            print("   Reason: \(reason)")
            print("   Code Meaning: \(getDisconnectCodeMeaning(code))")
            print("   Was Connected: \(isConnected ? "YES" : "NO")")
            print("   Current JID: \(jid ?? "nil")")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            
            isConnected = false
            
            // Create error with disconnect details
            let disconnectError = NSError(
                domain: "XMPPStream",
                code: Int(code),
                userInfo: [
                    NSLocalizedDescriptionKey: "WebSocket disconnected: \(reason)",
                    "disconnectCode": code,
                    "reason": reason
                ]
            )
            
            delegate?.xmppStreamDidDisconnect(self, error: disconnectError)
            
        case .text(let string):
            // Log raw XML from server (matching TypeScript behavior)
            // NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            // NSLog("📥 RECEIVED XML FROM SERVER (LENGTH: %lu):", string.count)
            // NSLog("%@", string)
            // NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            // print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            // print("📥 RECEIVED XML FROM SERVER (LENGTH: \(string.count)):")
            // print(string)
            // print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            
            // Handle stream features and authentication flow FIRST
            // This processes the raw XML and sends appropriate responses
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
                    // NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    // NSLog("✅ PARSED STANZA SUCCESSFULLY")
                    // NSLog("   Name: %@, Type: %@, From: %@, To: %@, ID: %@", 
                    //       stanza.name, 
                    //       stanza.attributes["type"] ?? "none",
                    //       stanza.attributes["from"] ?? "none",
                    //       stanza.attributes["to"] ?? "none",
                    //       stanza.attributes["id"] ?? "none")
                    // print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    // print("✅ PARSED STANZA SUCCESSFULLY")
                    // print("   Name: \(stanza.name), Type: \(stanza.attributes["type"] ?? "none"), From: \(stanza.attributes["from"] ?? "none"), To: \(stanza.attributes["to"] ?? "none"), ID: \(stanza.attributes["id"] ?? "none")")
                    
                    // Match TypeScript: Detect when stream becomes online
                    // In XMPP, after authentication, we receive a stream response or presence
                    // Check for successful authentication indicators
                    if !isConnected || jid == nil {
                        // Check if this is a stream response indicating successful auth
                        if stanza.name == "stream:stream" || 
                           (stanza.name == "stream" && stanza.attributes["xmlns"]?.contains("stream") == true) {
                            // Stream opened - we're connected
                            if let from = stanza.attributes["from"] {
                                self.jid = from
                                isConnected = true
                                NSLog("🔥🔥🔥 XMPP STREAM BECAME ONLINE 🔥🔥🔥")
                                print("🔥🔥🔥 XMPP STREAM BECAME ONLINE 🔥🔥🔥")
                                print("JID: \(from)")
                                delegate?.xmppStreamDidBecomeOnline(self, jid: from)
                            }
                        } else if stanza.name == "iq" && 
                                  stanza.attributes["type"] == "result" &&
                                  (stanza.attributes["id"]?.contains("bind") == true || 
                                   stanza.attributes["id"]?.contains("session") == true) {
                            // Successful bind/session establishment
                            if let from = stanza.attributes["from"] ?? jid {
                                self.jid = from
                                isConnected = true
                                delegate?.xmppStreamDidBecomeOnline(self, jid: from)
                            }
                        } else if stanza.name == "stream:features" || 
                                  (stanza.name == "features" && stanza.attributes["xmlns"]?.contains("stream") == true) {
                            // Stream features received - authentication can proceed
                            // This is handled automatically by the XMPP protocol
                        }
                    }
                    
                    // Send stanza to delegate (XMPPClient) which routes through HandleStanzas
                    // This ensures all stanzas go through the proper handler chain (HandleStanzas -> StanzaHandlers)
                    delegate?.xmppStream(self, didReceiveStanza: stanza)
                } else {
                    NSLog("⚠️⚠️⚠️ FAILED TO PARSE STANZA ⚠️⚠️⚠️")
                    NSLog("   Raw XML: %@", string)
                    print("⚠️⚠️⚠️ FAILED TO PARSE STANZA ⚠️⚠️⚠️")
                    print("   Raw XML: \(string)")
                }
            } else {
                NSLog("ℹ️ Stream-level element, not parsing as stanza")
                print("ℹ️ Stream-level element, not parsing as stanza")
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

// MARK: - XMPP Stanza Parser
class XMPPStanzaParser {
    static func parse(_ xmlString: String) -> XMPPStanza? {
        guard let data = xmlString.data(using: .utf8) else {
            print("⚠️ Failed to convert XML string to data")
            return nil
        }
        
        let parser = XMLParser(data: data)
        let delegate = XMPPStanzaParserDelegate()
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        
        let success = parser.parse()
        
        if !success {
            print("⚠️ XML parsing failed: \(parser.parserError?.localizedDescription ?? "unknown error")")
            if let error = parser.parserError {
                print("   Error domain: \(error._domain), code: \(error._code)")
            }
        }
        
        return delegate.rootStanza
    }
}

class XMPPStanzaParserDelegate: NSObject, XMLParserDelegate {
    var rootStanza: XMPPStanza?
    private var stack: [XMPPStanza] = []
    private var currentText: String = ""
    private var parseError: Error?
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        // Save any accumulated text to the previous element
        if !stack.isEmpty && !currentText.isEmpty {
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let lastIndex = stack.count - 1
                var last = stack[lastIndex]
                last.text = (last.text ?? "") + trimmed
                stack[lastIndex] = last
            }
            currentText = ""
        }
        
        // Create new stanza with attributes
        var finalAttributes = attributeDict
        
        // Add namespace to attributes if present (but don't override if already in attributes)
        if let namespaceURI = namespaceURI, !namespaceURI.isEmpty {
            if finalAttributes["xmlns"] == nil {
                finalAttributes["xmlns"] = namespaceURI
            }
        }
        
        let stanza = XMPPStanza(name: elementName, attributes: finalAttributes, children: [], text: nil)
        
        if stack.isEmpty {
            rootStanza = stanza
            stack.append(stanza)
        } else {
            // Add as child to the last element in stack
            let lastIndex = stack.count - 1
            var last = stack[lastIndex]
            last.children.append(stanza)
            stack[lastIndex] = last
            // Push new element onto stack
            stack.append(stanza)
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        // Save accumulated text to current element
        if !stack.isEmpty && !currentText.isEmpty {
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let lastIndex = stack.count - 1
                var last = stack[lastIndex]
                last.text = (last.text ?? "") + trimmed
                stack[lastIndex] = last
            }
            currentText = ""
        }
        
        // Pop the current element from stack
        if !stack.isEmpty {
            let completed = stack.removeLast()
            
            // If this was the root element, update rootStanza
            if stack.isEmpty {
                rootStanza = completed
            } else {
                // Update parent's reference to this child
                let parentIndex = stack.count - 1
                var parent = stack[parentIndex]
                // Find and update the child in parent's children array
                // Use lastIndex because we append children in order, so the last matching one is the one we just completed
                if let childIndex = parent.children.lastIndex(where: { $0.name == completed.name }) {
                    parent.children[childIndex] = completed
                    stack[parentIndex] = parent
                }
            }
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }
    
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
        print("⚠️ XML Parse Error: \(parseError.localizedDescription)")
        if let nsError = parseError as NSError? {
            print("   Domain: \(nsError.domain), Code: \(nsError.code)")
            print("   Line: \(parser.lineNumber), Column: \(parser.columnNumber)")
        }
    }
    
    func parser(_ parser: XMLParser, validationErrorOccurred validationError: Error) {
        print("⚠️ XML Validation Error: \(validationError.localizedDescription)")
    }
}

