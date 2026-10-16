//
//  CallOperations.swift
//  XMPPChatCore
//
//  Direct-chat call signalling stanzas. Mirrors sendCallInviteSignal and
//  sendCallStateSignal in src/networking/callTokenStanza.ts. Both go straight
//  to the peer's JID because the room may not be joined by the callee yet.
//

import Foundation

extension XMPPOperations {
    /// Tells the peer the call kind before the server call-token arrives.
    /// Best-effort: missing the hint only means the callee starts in the
    /// default kind until media is negotiated.
    public func sendCallInvite(
        kind: CallKind,
        peerXmppUsername: String,
        roomBareName: String,
        callId: String = ""
    ) {
        guard let stream = client?.xmppStream,
              let host = client?.host, !host.isEmpty,
              !peerXmppUsername.isEmpty else {
            return
        }
        let stanza = CallSignaling.buildCallInviteStanza(
            peerJid: CallSignaling.peerJid(peerXmppUsername, host: host),
            messageId: "call-invite-\(Int64(Date().timeIntervalSince1970 * 1000))",
            kind: kind,
            roomBareName: roomBareName,
            callId: callId
        )
        stream.send(stanza)
    }

    /// Tells the peer the call ended, was cancelled, or was declined.
    public func sendCallState(
        state: CallSignalState,
        peerXmppUsername: String,
        callId: String,
        roomBareName: String
    ) {
        guard let stream = client?.xmppStream,
              let host = client?.host, !host.isEmpty,
              !peerXmppUsername.isEmpty else {
            return
        }
        let stanza = CallSignaling.buildCallStateStanza(
            peerJid: CallSignaling.peerJid(peerXmppUsername, host: host),
            messageId: "call-state-\(Int64(Date().timeIntervalSince1970 * 1000))",
            state: state,
            roomBareName: roomBareName,
            callId: callId
        )
        stream.send(stanza)
    }
}
