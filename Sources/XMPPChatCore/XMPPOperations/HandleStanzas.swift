//
//  HandleStanzas.swift
//  XMPPChatCore
//
//  Routes incoming XMPP stanzas to appropriate handlers
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
        if stanza.attributes["type"] == "headline" {
            return
        }

        // MUC-Sub (XEP-0296 via ejabberd `mod_mucsub`) delivers every room-scoped
        // stanza — real-time messages, typing indicators, deletions, edits,
        // reactions — wrapped as a pubsub event:
        //   <message from="room@conference" id="...">
        //     <event xmlns="http://jabber.org/protocol/pubsub#event">
        //       <items node="urn:xmpp:mucsub:nodes:messages">
        //         <item id="..."><message ...>...(the real stanza)...</message></item>
        //       </items>
        //     </event>
        //   </message>
        // Every downstream handler (onRealtimeMessage, handleComposing,
        // onReactionMessage, onDeleteMessage, onEditMessage, …) expects the
        // plain inner stanza. Unwrap once here so the rest of the pipeline
        // stays unchanged. Observed live with ethora ejabberd — see wire log
        // from 2026-04-23 where diag_test_123 arrived only via mucsub wrapper.
        let dispatchStanza: XMPPStanza = {
            guard stanza.name == "message" else { return stanza }
            guard let event = stanza.getChild("event", xmlns: "http://jabber.org/protocol/pubsub#event"),
                  let items = event.getChild("items"),
                  let item = items.getChild("item"),
                  let inner = item.getChild("message") else {
                return stanza
            }
            return inner
        }()

        switch dispatchStanza.name {
        case "message":
            stanzaHandlers.onMessageError(dispatchStanza, client: client)
            stanzaHandlers.onReactionMessage(dispatchStanza)
            stanzaHandlers.onReactionHistory(dispatchStanza)
            stanzaHandlers.onDeleteMessage(dispatchStanza)
            stanzaHandlers.onEditMessage(dispatchStanza)
            stanzaHandlers.onChatInvite(dispatchStanza, client: client)
            stanzaHandlers.onRealtimeMessage(dispatchStanza)
            stanzaHandlers.onMessageHistory(dispatchStanza)
            if let username = client?.username {
                stanzaHandlers.handleComposing(dispatchStanza, currentUser: username)
            }
            stanzaHandlers.onPresenceInRoom(dispatchStanza)

        case "presence":
            stanzaHandlers.onRoomKicked(dispatchStanza)
            stanzaHandlers.onPresenceInRoom(dispatchStanza)

        case "iq":
            stanzaHandlers.onIQError(dispatchStanza)
            stanzaHandlers.onGetChatRooms(dispatchStanza, client: client)
            stanzaHandlers.onPresenceInRoom(dispatchStanza)
            stanzaHandlers.onGetRoomInfo(dispatchStanza)
            stanzaHandlers.onGetLastMessageArchive(dispatchStanza)

        case "room-config":
            stanzaHandlers.onNewRoomCreated(dispatchStanza, client: client)

        default:
            break
        }
    }
}

