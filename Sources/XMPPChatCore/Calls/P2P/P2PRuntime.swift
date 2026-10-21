//
//  P2PRuntime.swift
//  XMPPChatCore
//
//  The glue between the XMPP stanza stream and the per-call controller (which
//  lives in XMPPChatUI, next to the WebRTC dependency). Holds the signal inbox,
//  filters incoming `call-p2p` stanzas and sends outgoing ones. Mirrors
//  src/calls/p2p/p2pRuntime.ts.
//

import Foundation

@MainActor
public final class P2PRuntime {
    public static let shared = P2PRuntime()

    /// Signals that arrive for a call nobody is handling yet wait here.
    public let inbox = P2PSignalInbox()

    private init() {}

    /// Entry point for an incoming `<data type="call-p2p">` message. Stale,
    /// replayed, malformed or self-sent signals are dropped; the rest go to the
    /// inbox, which delivers or briefly holds them.
    public func handle(inner: XMPPStanza, selfXmppUsername: String) {
        guard let signal = P2PSignalCodec.parse(inner), !signal.fromLocal.isEmpty else { return }
        guard P2PSignalCodec.isFresh(signal) else { return }
        let selfLocal = (selfXmppUsername.split(separator: "@", omittingEmptySubsequences: false).first.map(String.init) ?? "")
            .lowercased()
        if signal.fromLocal == selfLocal { return }
        inbox.receive(signal)
    }

    /// Sends one signal to the peer over the live XMPP client.
    @discardableResult
    public func send(
        peerXmppUsername: String,
        callId: String,
        signal: P2PSignalName,
        payload: P2PSignalPayload
    ) -> Bool {
        guard let operations = ClientRegistry.shared.getGlobalXMPPClient()?.operations else { return false }
        return operations.sendP2PSignal(
            peerXmppUsername: peerXmppUsername,
            callId: callId,
            signal: signal,
            payload: payload
        )
    }
}
