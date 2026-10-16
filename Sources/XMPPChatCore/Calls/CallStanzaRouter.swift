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
    static func handle(inner: XMPPStanza, outer: XMPPStanza, selfXmppUsername: String) -> Bool {
        guard let result = CallSignaling.parseIncoming(inner: inner, outer: outer) else {
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
