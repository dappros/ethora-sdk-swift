//
//  XMPPStream_XMPPFramework.swift
//  XMPPChatCore
//
//  XMPPFramework-based XMPP Stream implementation
//  This replaces the manual WebSocket implementation with XMPPFramework
//

import Foundation

#if canImport(XMPPFramework)
import XMPPFramework

// MARK: - XMPPFramework-based Implementation
public class XMPPStream_XMPPFramework {
    private var xmppStream: XMPPStream?
    private var xmppReconnect: XMPPReconnect?
    private var xmppAutoPing: XMPPAutoPing?
    
    public private(set) var jid: String?
    private var isConnected: Bool = false
    private var stanzaHandlers: [(XMPPStanza) -> Void] = []
    
    // Store credentials
    private var username: String?
    private var password: String?
    private var resource: String = "default"
    private var host: String?
    private var port: UInt16 = 5443
    
    public weak var delegate: XMPPStreamDelegate?
    
    public required init(service: String) {
        guard let url = URL(string: service),
              let hostComponent = url.host else {
            fatalError("Invalid XMPP service URL: \(service)")
        }
        
        self.host = hostComponent
        if let portComponent = url.port {
            self.port = UInt16(portComponent)
        } else if url.scheme == "wss" {
            self.port = 5443
        }
        
        setupXMPPStream()
    }
    
    private func setupXMPPStream() {
        guard let host = host else { return }
        
        // Create XMPPFramework's XMPPStream
        xmppFrameworkStream = XMPPFramework.XMPPStream()
        xmppFrameworkStream?.hostName = host
        xmppFrameworkStream?.hostPort = port
        xmppFrameworkStream?.startTLSPolicy = .required
        
        // Enable WebSocket if available
        // Note: XMPPFramework may need additional setup for WebSocket
        
        // Setup reconnect
        xmppReconnect = XMPPReconnect()
        if let stream = xmppFrameworkStream {
            xmppReconnect?.activate(stream)
        }
        
        // Setup auto ping
        xmppAutoPing = XMPPAutoPing()
        xmppAutoPing?.pingInterval = 60
        if let stream = xmppFrameworkStream {
            xmppAutoPing?.activate(stream)
        }
        
        // Add delegate
        xmppFrameworkStream?.addDelegate(self, delegateQueue: DispatchQueue.main)
    }
    
    public func connect(username: String, password: String, resource: String = "default") {
        self.username = username
        self.password = password
        self.resource = resource
        
        guard let stream = xmppFrameworkStream else { return }
        
        // Set JID
        let jidString = "\(username)@\(host ?? "")/\(resource)"
        stream.myJID = XMPPJID(string: jidString)
        
        self.jid = jidString
        
        NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        NSLog("📤 CONNECTING WITH XMPPFRAMEWORK")
        NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        NSLog("   Host: %@", host ?? "unknown")
        NSLog("   Port: %u", port)
        NSLog("   Username: %@", username)
        NSLog("   JID: %@", jidString)
        NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📤 CONNECTING WITH XMPPFRAMEWORK")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("   Host: \(host ?? "unknown")")
        print("   Port: \(port)")
        print("   Username: \(username)")
        print("   JID: \(jidString)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        do {
            try stream.connect(withTimeout: XMPPStreamTimeoutNone)
        } catch {
            NSLog("❌ Error connecting: %@", error.localizedDescription)
            print("❌ Error connecting: \(error.localizedDescription)")
            delegate?.xmppStreamDidDisconnect(self, error: error)
        }
    }
    
    public func disconnect() {
        xmppFrameworkStream?.disconnect()
        isConnected = false
    }
    
    public func send(_ stanza: XMPPStanza) {
        // Convert our XMPPStanza to XMPPFramework's DDXMLElement
        let xmlString = stanza.toXML()
        if let element = try? DDXMLElement(xmlString: xmlString) {
            xmppFrameworkStream?.send(element)
            delegate?.xmppStream(self, didSendStanza: stanza)
        }
    }
    
    public func send(_ xml: String) {
        if let element = try? DDXMLElement(xmlString: xml) {
            xmppFrameworkStream?.send(element)
        }
    }
    
    public func on(_ event: String, handler: @escaping (XMPPStanza) -> Void) {
        stanzaHandlers.append(handler)
    }
    
    public func off(_ event: String, handler: @escaping (XMPPStanza) -> Void) {
        if let index = stanzaHandlers.firstIndex(where: { $0 as AnyObject === handler as AnyObject }) {
            stanzaHandlers.remove(at: index)
        }
    }
}

// MARK: - XMPPFramework XMPPStreamDelegate
extension XMPPStream_XMPPFramework: XMPPFramework.XMPPStreamDelegate {
    public func xmppStreamDidConnect(_ sender: XMPPFramework.XMPPStream!) {
        NSLog("✅ XMPP STREAM CONNECTED")
        print("✅ XMPP STREAM CONNECTED")
        
        isConnected = true
        delegate?.xmppStreamDidConnect(self)
        
        // Authenticate
        if let password = password {
            do {
                try sender.authenticate(withPassword: password)
                NSLog("📤 SENDING AUTHENTICATION")
                print("📤 SENDING AUTHENTICATION")
            } catch {
                NSLog("❌ Error authenticating: %@", error.localizedDescription)
                print("❌ Error authenticating: \(error.localizedDescription)")
            }
        }
    }
    
    public func xmppStreamDidAuthenticate(_ sender: XMPPFramework.XMPPStream!) {
        NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        NSLog("✅ STEP 3: XMPP AUTHENTICATION SUCCESS")
        NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("✅ STEP 3: XMPP AUTHENTICATION SUCCESS")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        if let jid = sender.myJID {
            self.jid = jid.full
            NSLog("   JID: %@", jid.full)
            print("   JID: \(jid.full)")
            delegate?.xmppStreamDidBecomeOnline(self, jid: jid.full)
        }
    }
    
    public func xmppStream(_ sender: XMPPFramework.XMPPStream!, didNotAuthenticate error: DDXMLElement!) {
        NSLog("❌ XMPP AUTHENTICATION FAILED")
        print("❌ XMPP AUTHENTICATION FAILED")
        if let errorXML = error {
            NSLog("   Error: %@", errorXML.xmlString)
            print("   Error: \(errorXML.xmlString)")
        }
    }
    
    public func xmppStreamDidDisconnect(_ sender: XMPPFramework.XMPPStream!, withError error: Error!) {
        NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        NSLog("❌ XMPP STREAM DISCONNECTED")
        NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        if let error = error {
            NSLog("   Error: %@", error.localizedDescription)
            print("   Error: \(error.localizedDescription)")
        }
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("❌ XMPP STREAM DISCONNECTED")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        isConnected = false
        delegate?.xmppStreamDidDisconnect(self, error: error)
    }
    
    public func xmppStream(_ sender: XMPPFramework.XMPPStream!, didReceive iq: XMPPIQ!) {
        // Convert XMPPIQ to our XMPPStanza format
        if let stanza = convertDDXMLElementToStanza(iq) {
            for handler in stanzaHandlers {
                handler(stanza)
            }
            delegate?.xmppStream(self, didReceiveStanza: stanza)
        }
    }
    
    public func xmppStream(_ sender: XMPPFramework.XMPPStream!, didReceive message: XMPPMessage!) {
        // Convert XMPPMessage to our XMPPStanza format
        if let stanza = convertDDXMLElementToStanza(message) {
            for handler in stanzaHandlers {
                handler(stanza)
            }
            delegate?.xmppStream(self, didReceiveStanza: stanza)
        }
    }
    
    public func xmppStream(_ sender: XMPPFramework.XMPPStream!, didReceive presence: XMPPPresence!) {
        // Convert XMPPPresence to our XMPPStanza format
        if let stanza = convertDDXMLElementToStanza(presence) {
            for handler in stanzaHandlers {
                handler(stanza)
            }
            delegate?.xmppStream(self, didReceiveStanza: stanza)
        }
    }
    
    // Helper to convert DDXMLElement to our XMPPStanza
    private func convertDDXMLElementToStanza(_ element: DDXMLElement) -> XMPPStanza? {
        let name = element.name ?? ""
        var attributes: [String: String] = [:]
        
        // Copy attributes
        if let xmlAttributes = element.attributes {
            for attr in xmlAttributes {
                if let attr = attr as? DDXMLNode,
                   let name = attr.name,
                   let value = attr.stringValue {
                    attributes[name] = value
                }
            }
        }
        
        // Convert children
        var children: [XMPPStanza] = []
        if let xmlChildren = element.children {
            for child in xmlChildren {
                if let child = child as? DDXMLElement,
                   let childStanza = convertDDXMLElementToStanza(child) {
                    children.append(childStanza)
                }
            }
        }
        
        return XMPPStanza(name: name, attributes: attributes, children: children, text: element.stringValue)
    }
}

#else
// Fallback: If XMPPFramework is not available, provide a stub
public class XMPPStream_XMPPFramework {
    public init(service: String) {
        fatalError("XMPPFramework is not available. Please integrate XMPPFramework first.")
    }
    
    public func connect(username: String, password: String, resource: String = "default") {
        fatalError("XMPPFramework is not available.")
    }
    
    public func disconnect() {}
    public func send(_ stanza: XMPPStanza) {}
    public func send(_ xml: String) {}
    public func on(_ event: String, handler: @escaping (XMPPStanza) -> Void) {}
    public func off(_ event: String, handler: @escaping (XMPPStanza) -> Void) {}
}
#endif

