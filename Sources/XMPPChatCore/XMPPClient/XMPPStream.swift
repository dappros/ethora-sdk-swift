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
        
        socket?.connect()
    }
    
    public func disconnect() {
        socket?.disconnect()
        socket = nil
        isConnected = false
        authState = .notStarted
    }
    
    /// Check if the stream is currently connected and ready to send
    public func checkConnected() -> Bool {
        return isConnected && socket != nil
    }
    
    public func send(_ stanza: XMPPStanza) {
        let xml = stanza.toXML()
        
        guard let socket = socket else {
            //print("❌ XMPPStream.send: Cannot send stanza - socket is nil")
            let error = NSError(
                domain: "XMPPStream",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot send: socket is nil"]
            )
            delegate?.xmppStream(self, didReceiveError: error)
            return
        }
        
        guard isConnected else {
            //print("❌ XMPPStream.send: Cannot send stanza - not connected")
            let error = NSError(
                domain: "XMPPStream",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Cannot send: not connected"]
            )
            delegate?.xmppStream(self, didReceiveError: error)
            return
        }
        
        socket.write(string: xml)
        delegate?.xmppStream(self, didSendStanza: stanza)
    }
    
    public func send(_ xml: String) {
        guard let socket = socket else {
            //print("❌ XMPPStream.send: Cannot send XML - socket is nil")
            return
        }
        
        guard isConnected else {
            //print("❌ XMPPStream.send: Cannot send XML - not connected")
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
    
    internal func parseStanza(_ xmlString: String) -> XMPPStanza? {
        return XMPPStanzaParser.parse(xmlString)
    }
    
    // MARK: - Auth State
    
    internal var authState: AuthState = .notStarted
    private var streamId: String?
    
    internal enum AuthState {
        case notStarted
        case streamHeaderSent
        case streamFeaturesReceived
        case saslAuthSent
        case saslSuccess
        case bindSent
        case sessionSent
        case authenticated
    }

    // Helper to get disconnect code meaning
    internal func getDisconnectCodeMeaning(_ code: UInt16) -> String {
        switch code {
        case 1000:
            return "Normal closure (1000) - Connection closed normally"
        case 1001:
            return "Going away (1001) - Server or client is going away"
        case 1002:
            return "Protocol error (1002) - Termination due to protocol error"
        case 1003:
            return "Unsupported data (1003) - Received data of a type it cannot accept"
        case 1005:
            return "No status received (1005)"
        case 1006:
            return "Abnormal closure (1006)"
        case 1007:
            return "Invalid payload (1007)"
        case 1008:
            return "Policy violation (1008)"
        case 1009:
            return "Message too big (1009)"
        case 1011:
            return "Internal error (1011)"
        case 1015:
            return "TLS handshake failure (1015) - TLS handshake failed"
        default:
            return "Unknown code (\(code))"
        }
    }
}

// MARK: - Conditional Type Alias
#if canImport(XMPPFramework)
public typealias XMPPStream = XMPPStream_XMPPFramework
#else
public typealias XMPPStream = XMPPStream_WebSocket
#endif
