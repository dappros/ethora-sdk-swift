//
//  CallSignaling.swift
//  XMPPChatCore
//
//  Pure parsing and stanza building for 1:1 call signalling. No state and no
//  I/O, so the same shapes can be unit-tested directly.
//  Translated from src/networking/callTokenStanza.ts (receive side) and the
//  sendCallStateSignal / sendCallInviteSignal builders (send side).
//

import Foundation

/// Decoded `<data type="call-token">`.
public struct IncomingCallToken: Equatable, Sendable {
    public let token: String
    /// Bare room name from the stanza `room` attribute (not the full JID).
    public let room: String
    /// Kind from the stanza. The server does not always set it, so the client
    /// can override it with a `call-invite` hint.
    public let stanzaKind: CallKind
    public let callId: String?
    /// Caller display name from the JWT `sub` claim, when it is not a raw id.
    public let callerName: String
    /// Call id from the JWT `metadata.callId` claim, when present.
    public let jwtCallId: String?
}

/// What an incoming call stanza means for local state. Produced by
/// `CallSignaling.parseIncoming`, applied on the main actor by `CallStore`.
public enum CallSignalEvent: Equatable, Sendable {
    case token(IncomingCallToken)
    case invite(room: String?, callId: String?, kind: CallKind)
    case state(
        state: String,
        callId: String?,
        room: String?,
        callLog: CallLogMeta?
    )
}

public enum CallSignaling {
    /// A call-token older than this is ignored (replayed or stale).
    public static let maxCallTokenAgeMs: Int64 = 5_000
    /// How long a call-invite kind hint is kept for the matching token.
    public static let kindHintTTL: TimeInterval = 60

    /// Body text the server can use to broadcast call signalling into a MUC.
    /// These must never be shown as chat messages.
    public static let bodyKeywords: Set<String> = [
        "call-token", "call-state", "call-ringing", "call-ended", "call-declined",
        "call-cancelled", "call-canceled", "call-timeout", "call-rejected",
    ]

    // MARK: - Element helpers

    /// The direct `<data type="call-*">` child of a message, if any.
    public static func callDataElement(in stanza: XMPPStanza) -> XMPPStanza? {
        guard let data = stanza.getChild("data"),
              let type = data.attributes["type"],
              type.lowercased().hasPrefix("call-") else {
            return nil
        }
        return data
    }

    public static func dataType(of data: XMPPStanza) -> String {
        (data.attributes["type"] ?? "").lowercased()
    }

    /// First non-empty, trimmed attribute value among `keys`.
    public static func firstAttribute(_ attributes: [String: String], keys: [String]) -> String? {
        for key in keys {
            let value = (attributes[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }

    /// Localpart of a JID or XMPP username (`alice@host` -> `alice`).
    public static func localPart(of jidOrUsername: String) -> String {
        String(jidOrUsername.split(separator: "@", omittingEmptySubsequences: false).first ?? "")
    }

    /// Full JID for a peer, appending the host when only a localpart is given.
    public static func peerJid(_ peer: String, host: String) -> String {
        peer.contains("@") ? peer : "\(peer)@\(host)"
    }

    // MARK: - Freshness

    /// Milliseconds timestamp from a `stanza-id` value. Accepts a bare numeric
    /// id (ms or a 16-digit value whose first 13 digits are ms) or any string
    /// containing a 13+ digit run.
    public static func extractNumericTimestamp(_ value: String?) -> Int64? {
        let source = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return nil }

        if let direct = Int64(source), direct > 0 {
            return source.count > 13 ? Int64(String(source.prefix(13))) : direct
        }

        guard let range = source.range(of: #"\d{13,}"#, options: .regularExpression) else {
            return nil
        }
        return Int64(String(source[range].prefix(13)))
    }

    /// True when the `stanza-id` timestamp is within `maxCallTokenAgeMs` of now.
    public static func isFreshCallToken(stanzaIdValue: String?, now: Date = Date()) -> Bool {
        guard let createdMs = extractNumericTimestamp(stanzaIdValue) else { return false }
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        return abs(nowMs - createdMs) <= maxCallTokenAgeMs
    }

    // MARK: - JWT (read only, not verified)

    /// Payload of a JWT. Signature is not checked here: LiveKit rejects a
    /// tampered token on connect, and the client only reads display claims.
    public static func decodeJwtPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }

        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)

        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    /// The JWT `sub` claim as a display name. Raw id-like values are dropped
    /// so an opaque id is never shown as a caller name.
    public static func callerDisplayName(fromJwt payload: [String: Any]?) -> String {
        guard let sub = payload?["sub"] as? String else { return "" }
        let trimmed = sub.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        if trimmed.range(of: #"^[0-9a-fA-F_-]{16,}$"#, options: .regularExpression) != nil {
            return ""
        }
        return trimmed
    }

    /// Call id from the JWT `metadata` claim. The claim may be a JSON string or
    /// an object.
    public static func callId(fromJwt payload: [String: Any]?) -> String? {
        guard let metadata = payload?["metadata"] else { return nil }

        let object: [String: Any]?
        if let text = metadata as? String, let data = text.data(using: .utf8) {
            object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        } else {
            object = metadata as? [String: Any]
        }

        guard let id = object?["callId"] else { return nil }
        let text = String(describing: id).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    // MARK: - Peer

    /// For a 1:1 room named `<userA>-<userB>`, the localpart of the other user.
    public static func derivePeerXmppUsername(bareRoomName: String, selfXmppUsername: String) -> String? {
        guard bareRoomName.contains("-") else { return nil }
        let parts = bareRoomName.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { return nil }
        let selfLocal = localPart(of: selfXmppUsername)
        return parts.first { !$0.isEmpty && $0 != selfLocal }
    }

    // MARK: - call-state

    public static func isTerminalState(_ state: String) -> Bool {
        ["ended", "declined", "cancelled", "canceled", "timeout", "rejected"]
            .contains(state.lowercased())
    }

    /// A server call-log carries a caller and/or a duration. Bare client
    /// signals (state only) carry neither.
    public static func hasCallLogData(_ attributes: [String: String]) -> Bool {
        let caller = (attributes["callerXmppUsername"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !caller.isEmpty { return true }
        if let duration = attributes["durationMs"], !duration.isEmpty { return true }
        return false
    }

    /// Call-log metadata from a call-state `<data>`, or nil if it is not a log.
    public static func callLogMeta(fromAttributes attributes: [String: String]) -> CallLogMeta? {
        guard hasCallLogData(attributes) else { return nil }
        let callId = firstAttribute(attributes, keys: ["callId", "callid"]) ?? ""
        let duration = Int64(attributes["durationMs"] ?? "") ?? 0
        let kind: CallKind = (attributes["kind"] ?? "").lowercased() == "audio" ? .audio : .video
        let caller = firstAttribute(attributes, keys: ["callerXmppUsername"]).map(localPart(of:))
        return CallLogMeta(
            callId: callId,
            durationMs: duration,
            kind: kind,
            callerXmppUsername: caller
        )
    }

    // MARK: - Parsing

    /// Classifies an inbound message. `inner` is the unwrapped message (MUC-Sub
    /// wrapper removed) and `outer` is the stanza as received, used for the
    /// `from` attribute and as a `stanza-id` fallback.
    ///
    /// Returns nil when the stanza is not call signalling. The caller then
    /// continues with the normal chat pipeline.
    ///
    /// `swallow` is true when the stanza must not reach chat handlers. Call-log
    /// entries (call-state with log data) are the exception: they are shown in
    /// the chat, so they flow on after the state event is applied.
    public static func parseIncoming(
        inner: XMPPStanza,
        outer: XMPPStanza,
        now: Date = Date()
    ) -> (swallow: Bool, event: CallSignalEvent?)? {
        guard inner.name == "message" else { return nil }

        if let data = callDataElement(in: inner) {
            switch dataType(of: data) {
            case "call-state":
                let attributes = data.attributes
                let fromRoom = localPart(of: String((outer.attributes["from"] ?? "").split(separator: "/").first ?? ""))
                let event = CallSignalEvent.state(
                    state: (attributes["state"] ?? attributes["event"] ?? "").lowercased(),
                    callId: firstAttribute(attributes, keys: ["callId", "callid"]),
                    room: firstAttribute(attributes, keys: ["room"]) ?? (fromRoom.isEmpty ? nil : fromRoom),
                    callLog: callLogMeta(fromAttributes: attributes)
                )
                return (swallow: !hasCallLogData(attributes), event: event)

            case "call-invite":
                let kind: CallKind = (data.attributes["kind"] ?? "").lowercased() == "audio" ? .audio : .video
                let event = CallSignalEvent.invite(
                    room: firstAttribute(data.attributes, keys: ["room"]),
                    callId: firstAttribute(data.attributes, keys: ["callId", "callid"]),
                    kind: kind
                )
                return (swallow: true, event: event)

            case "call-token":
                let token = (data.attributes["token"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let room = (data.attributes["room"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let stanzaKind: CallKind = (data.attributes["kind"] ?? "").lowercased() == "audio" ? .audio : .video

                // Freshness is checked here, at arrival, like the web handler.
                let stanzaIdValue = inner.getChild("stanza-id")?.attributes["id"]
                    ?? outer.getChild("stanza-id")?.attributes["id"]
                guard !token.isEmpty, !room.isEmpty,
                      isFreshCallToken(stanzaIdValue: stanzaIdValue, now: now) else {
                    return (swallow: true, event: nil)
                }

                let payload = decodeJwtPayload(token)
                let event = CallSignalEvent.token(
                    IncomingCallToken(
                        token: token,
                        room: room,
                        stanzaKind: stanzaKind,
                        callId: firstAttribute(data.attributes, keys: ["callId", "callid"]),
                        callerName: callerDisplayName(fromJwt: payload),
                        jwtCallId: callId(fromJwt: payload)
                    )
                )
                return (swallow: true, event: event)

            default:
                // Unknown call-* signalling: swallow so it never reaches chat.
                return (swallow: true, event: nil)
            }
        }

        // Legacy servers may broadcast signalling as plain body text.
        if let body = inner.getChildText("body")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !body.isEmpty, bodyKeywords.contains(body) {
            if body.hasPrefix("call-") {
                let state = String(body.dropFirst("call-".count))
                return (swallow: true, event: .state(state: state, callId: nil, room: nil, callLog: nil))
            }
            return (swallow: true, event: nil)
        }

        return nil
    }

    // MARK: - Outgoing stanzas

    /// `<message type="chat"><data type="call-invite" .../></message>`. Sent
    /// straight to the peer before the REST create, so the callee learns the
    /// call kind (the server does not carry it on the call-token).
    public static func buildCallInviteStanza(
        peerJid: String,
        messageId: String,
        kind: CallKind,
        roomBareName: String,
        callId: String
    ) -> XMPPStanza {
        XMPPStanza(
            name: "message",
            attributes: ["to": peerJid, "type": "chat", "id": messageId],
            children: [
                XMPPStanza(
                    name: "data",
                    attributes: [
                        "type": "call-invite",
                        "kind": kind.rawValue,
                        "room": roomBareName,
                        "callId": callId,
                    ]
                ),
            ]
        )
    }

    /// `<message type="chat"><data type="call-state" state="..." .../></message>`
    /// sent to the peer on hang-up, cancel, decline or reject.
    public static func buildCallStateStanza(
        peerJid: String,
        messageId: String,
        state: CallSignalState,
        roomBareName: String,
        callId: String
    ) -> XMPPStanza {
        XMPPStanza(
            name: "message",
            attributes: ["to": peerJid, "type": "chat", "id": messageId],
            children: [
                XMPPStanza(
                    name: "data",
                    attributes: [
                        "type": "call-state",
                        "state": state.rawValue,
                        "callId": callId,
                        "room": roomBareName,
                    ]
                ),
            ]
        )
    }
}
