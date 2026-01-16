//
//  ClientRegistry.swift
//  XMPPChatCore
//
//  Global XMPP client registry
//

import Foundation

public class ClientRegistry {
    public static let shared = ClientRegistry()
    
    private var client: XMPPClient?
    
    private init() {}
    
    public func setGlobalXMPPClient(_ client: XMPPClient?) {
        self.client = client
    }
    
    public func getGlobalXMPPClient() -> XMPPClient? {
        return client
    }
    
    public func requireXMPPClient() -> XMPPClient {
        guard let client = client else {
            fatalError("XMPP Client is not initialized. Call setGlobalXMPPClient first.")
        }
        return client
    }
}
