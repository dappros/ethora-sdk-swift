//
//  ChatRoomViewModel+XMPP.swift
//  XMPPChatUI
//

import Foundation
import XMPPChatCore

extension ChatRoomViewModel {
    public func xmppClientDidConnect(_ client: XMPPClient) {
        // print("📡 ChatRoomViewModel: XMPP client connected")
    }
    
    public func xmppClientDidDisconnect(_ client: XMPPClient) {
        // print("📡 ChatRoomViewModel: XMPP client disconnected")
    }
    
    public func xmppClient(_ client: XMPPClient, didReceiveMessage message: Message) {
        // Handle the incoming message
        handleIncomingMessage(message)
    }
    
    public func xmppClient(_ client: XMPPClient, didReceiveStanza stanza: XMPPStanza) {
        // Stanza received - already handled by handleStanza
    }
    
    public func xmppClient(_ client: XMPPClient, didChangeStatus status: ConnectionStatus) {
        // print("📡 ChatRoomViewModel: Connection status changed: \(status.rawValue)")
    }
}
