//
//  CallPush.swift
//  XMPPChatCore
//
//  Recognises and parses an incoming-call push (APNs / FCM data payload).
//  Calls normally ring through a live XMPP `call-token` stanza, which is missed
//  while the app is backgrounded or closed, so the backend also delivers the
//  call over push. Mirrors src/helpers/callPush.ts. Hosts feed the result to
//  `CallStore.applyPush` (and to CallKit if they use it).
//

import Foundation

public struct CallPush: Equatable, Sendable {
    public var callId: String?
    /// LiveKit token, empty for a p2p call.
    public var token: String?
    public var kind: CallKind
    public var mode: CallMode
    public var isGroup: Bool
    /// Bare room name (JID localpart).
    public var roomBareName: String?
    /// Raw room reference from the payload (full JID or bare name).
    public var roomRef: String?
    public var callerName: String?
    public var callerXmppUsername: String?

    private static func pick(_ data: [AnyHashable: Any], _ keys: [String]) -> String {
        for key in keys {
            if let value = data[key] {
                let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            }
        }
        return ""
    }

    /// True when a push payload represents an incoming call. Matches on an
    /// explicit call marker or on a callId paired with a call specific field,
    /// so a normal message push is never misread as a call.
    public static func isCallPush(_ data: [AnyHashable: Any]) -> Bool {
        let marker = pick(data, ["type", "pushType", "category", "messageType", "event"]).lowercased()
        if ["call", "incoming-call", "call-token", "call-invite"].contains(marker) { return true }
        let callId = pick(data, ["callId", "callid", "callID"])
        let kind = pick(data, ["kind"]).lowercased()
        let hasCallField = !pick(data, ["callToken", "livekitToken"]).isEmpty
            || !pick(data, ["callKind"]).isEmpty
            || kind == "audio" || kind == "video"
        return !callId.isEmpty && hasCallField
    }

    public static func parse(_ data: [AnyHashable: Any]) -> CallPush {
        let roomRef = pick(data, ["callRoom", "room", "roomJid", "jid", "chatId"])
        let bare = roomRef.split(separator: "@", omittingEmptySubsequences: false).first.map(String.init) ?? roomRef
        let kindRaw = pick(data, ["callKind", "kind"]).lowercased()
        let callId = pick(data, ["callId", "callid", "callID"])
        let token = pick(data, ["callToken", "livekitToken", "token"])
        let caller = pick(data, ["callerXmppUsername", "callerUsername", "userJid", "senderJid"])
        let callerLocal = caller.split(separator: "@", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let name = pick(data, ["callerName", "callerDisplayName", "senderName", "title"])
        let groupText = pick(data, ["group", "isGroup"]).lowercased()
        let mode: CallMode = pick(data, ["mode"]).lowercased() == "p2p" ? .p2p : .livekit
        return CallPush(
            callId: callId.isEmpty ? nil : callId,
            token: token.isEmpty ? nil : token,
            kind: kindRaw == "audio" ? .audio : .video,
            mode: mode,
            isGroup: groupText == "true" || groupText == "1",
            roomBareName: bare.isEmpty ? nil : bare,
            roomRef: roomRef.isEmpty ? nil : roomRef,
            callerName: name.isEmpty ? nil : name,
            callerXmppUsername: callerLocal.isEmpty ? nil : callerLocal
        )
    }
}
