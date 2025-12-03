//
//  HandleStanzas.swift
//  XMPPChatCore
//
//  Routes incoming XMPP stanzas to appropriate handlers
//  Translated from handleStanzas.xmpp.ts
//

import Foundation

public class HandleStanzas {
    private let stanzaHandlers: StanzaHandlers
    private weak var client: XMPPClient?
    
    public init(client: XMPPClient, stanzaHandlers: StanzaHandlers) {
        self.client = client
        self.stanzaHandlers = stanzaHandlers
    }
    
    /// Main entry point for handling stanzas
    /// Matches TypeScript: handleStanza(stanza: Element, xmppWs: XmppClient)
    public func handleStanza(_ stanza: XMPPStanza) {
        // Match TypeScript: if (stanza?.attrs?.type === 'headline') return;
        if stanza.attributes["type"] == "headline" {
            return
        }
        
        // Match TypeScript: switch (stanza.name) { ... }
        switch stanza.name {
        case "message":
            // Match TypeScript order exactly:
            // onMessageError(stanza, xmppWs);
            stanzaHandlers.onMessageError(stanza, client: client)
            // onReactionMessage(stanza);
            stanzaHandlers.onReactionMessage(stanza)
            // onReactionHistory(stanza);
            stanzaHandlers.onReactionHistory(stanza)
            // onDeleteMessage(stanza);
            stanzaHandlers.onDeleteMessage(stanza)
            // onEditMessage(stanza);
            stanzaHandlers.onEditMessage(stanza)
            // onChatInvite(stanza, xmppWs);
            stanzaHandlers.onChatInvite(stanza, client: client)
            // onRealtimeMessage(stanza);
            stanzaHandlers.onRealtimeMessage(stanza)
            // onMessageHistory(stanza);
            stanzaHandlers.onMessageHistory(stanza)
            // handleComposing(stanza, xmppWs.username);
            if let username = client?.username {
                stanzaHandlers.handleComposing(stanza, currentUser: username)
            }
            // onPresenceInRoom(stanza);
            stanzaHandlers.onPresenceInRoom(stanza)
            
        case "presence":
            // onRoomKicked(stanza);
            stanzaHandlers.onRoomKicked(stanza)
            // onPresenceInRoom(stanza);
            stanzaHandlers.onPresenceInRoom(stanza)
            
        case "iq":
            // onGetChatRooms(stanza, xmppWs);
            stanzaHandlers.onGetChatRooms(stanza, client: client)
            // onRealtimeMessage(stanza);
            stanzaHandlers.onRealtimeMessage(stanza)
            // onPresenceInRoom(stanza);
            stanzaHandlers.onPresenceInRoom(stanza)
            // onGetRoomInfo(stanza);
            stanzaHandlers.onGetRoomInfo(stanza)
            // onGetLastMessageArchive(stanza);
            stanzaHandlers.onGetLastMessageArchive(stanza)
            
        case "room-config":
            // onNewRoomCreated(stanza, xmppWs);
            stanzaHandlers.onNewRoomCreated(stanza, client: client)
            
        default:
            print("Unhandled stanza type: \(stanza.name)")
        }
    }
}

