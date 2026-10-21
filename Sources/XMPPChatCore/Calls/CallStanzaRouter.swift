//
//  CallStanzaRouter.swift
//  XMPPChatCore
//
//  Entry point for inbound call signalling, called from HandleStanzas before
//  the chat handlers. Parsing is synchronous. State changes run on the main
//  actor.
//

import Foundation

enum CallStanzaRouter {
    /// Returns true when the stanza is call signalling that must not reach the
    /// chat pipeline. Call-log entries return false so they are shown in the chat.
    static func handle(
        inner: XMPPStanza,
        outer: XMPPStanza,
        selfXmppUsername: String,
        xmppDomain: String? = nil
    ) -> Bool {
        // Peer to peer media signalling (offer / answer / candidate / end) goes to
        // the p2p runtime and never to the chat pipeline.
        if let data = CallSignaling.callDataElement(in: inner),
           CallSignaling.dataType(of: data) == P2PSignalCodec.dataType {
            Task { @MainActor in
                P2PRuntime.shared.handle(inner: inner, selfXmppUsername: selfXmppUsername)
            }
            return true
        }
        guard let result = CallSignaling.parseIncoming(
            inner: inner,
            outer: outer,
            expectedDomain: xmppDomain
        ) else {
            return false
        }
        if let event = result.event {
            Task { @MainActor in
                CallStore.shared.apply(event, selfXmppUsername: selfXmppUsername)
            }
        }
        return result.swallow
    }
}
