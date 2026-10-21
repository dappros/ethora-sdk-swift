//
//  P2PSignal.swift
//  XMPPChatCore
//
//  Wire format of the peer to peer call signalling. It travels as a direct
//  XMPP chat message between the two users, no server involvement:
//
//    <message type="chat" to="<peer bare jid>">
//      <body>system</body>
//      <data type="call-p2p" callId="..." signal="offer|answer|candidate|end"
//            payload="<JSON string>"/>
//    </message>
//
//  payload is {type, sdp} for offer/answer, {candidate, sdpMid, sdpMLineIndex,
//  usernameFragment} for candidate and {reason} for end. Mirrors
//  src/calls/p2p/signalStanza.ts. Builds and parses stanzas only, so it is
//  testable without a connection.
//

import Foundation

public enum P2PSignalName: String, Equatable, Sendable {
    case offer
    case answer
    case candidate
    case end
}

public struct P2PCandidatePayload: Equatable, Sendable {
    public var candidate: String
    public var sdpMid: String?
    public var sdpMLineIndex: Int?
    public var usernameFragment: String?

    public init(
        candidate: String,
        sdpMid: String? = nil,
        sdpMLineIndex: Int? = nil,
        usernameFragment: String? = nil
    ) {
        self.candidate = candidate
        self.sdpMid = sdpMid
        self.sdpMLineIndex = sdpMLineIndex
        self.usernameFragment = usernameFragment
    }
}

public enum P2PSignalPayload: Equatable, Sendable {
    /// Offer or answer description; `type` is "offer" or "answer".
    case sdp(type: String, sdp: String)
    case candidate(P2PCandidatePayload)
    case end(reason: String?)
}

public struct P2PSignal: Equatable, Sendable {
    public let callId: String
    public let name: P2PSignalName
    public let payload: P2PSignalPayload
    /// Sender's bare JID as written in `from` (lower-cased), "" when missing.
    public let fromBare: String
    /// Sender's xmpp localpart, "" when missing.
    public let fromLocal: String
    /// Age from the server's stanza-id timestamp, nil when the stanza has none.
    public let ageMs: Int64?
    /// Carries <delay/>: stored offline and replayed, so it is stale.
    public let delayed: Bool

    public init(
        callId: String,
        name: P2PSignalName,
        payload: P2PSignalPayload,
        fromBare: String = "",
        fromLocal: String = "",
        ageMs: Int64? = nil,
        delayed: Bool = false
    ) {
        self.callId = callId
        self.name = name
        self.payload = payload
        self.fromBare = fromBare
        self.fromLocal = fromLocal
        self.ageMs = ageMs
        self.delayed = delayed
    }
}

public enum P2PSignalCodec {
    public static let dataType = "call-p2p"
    /// Guards against a hostile peer pushing megabytes through an attribute.
    public static let maxSdpLength = 64 * 1024
    public static let maxCandidateLength = 2048
    public static let maxReasonLength = 64
    /// A signal older than this (server timestamp) is not part of a live
    /// negotiation.
    public static let maxSignalAgeMs: Int64 = 15_000

    // MARK: - Build

    public static func buildStanza(
        to: String,
        callId: String,
        name: P2PSignalName,
        payload: P2PSignalPayload,
        messageId: String
    ) -> XMPPStanza {
        XMPPStanza(
            name: "message",
            attributes: ["to": to, "type": "chat", "id": messageId],
            children: [
                XMPPStanza(name: "body", text: "system"),
                XMPPStanza(
                    name: "data",
                    attributes: [
                        "type": dataType,
                        "callId": callId,
                        "signal": name.rawValue,
                        "payload": encode(payload),
                    ]
                ),
                // Signalling is only meaningful live: keep it out of the
                // archive and the offline store.
                XMPPStanza(name: "no-store", attributes: ["xmlns": "urn:xmpp:hints"]),
                XMPPStanza(name: "no-permanent-store", attributes: ["xmlns": "urn:xmpp:hints"]),
            ]
        )
    }

    /// JSON string of the payload. JSON escapes newlines inside the SDP, so the
    /// attribute survives XML attribute-value normalisation.
    public static func encode(_ payload: P2PSignalPayload) -> String {
        var object: [String: Any] = [:]
        switch payload {
        case let .sdp(type, sdp):
            object = ["type": type, "sdp": sdp]
        case let .candidate(c):
            object["candidate"] = c.candidate
            if let mid = c.sdpMid { object["sdpMid"] = mid }
            if let index = c.sdpMLineIndex { object["sdpMLineIndex"] = index }
            if let ufrag = c.usernameFragment { object["usernameFragment"] = ufrag }
        case let .end(reason):
            if let reason { object["reason"] = reason }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    // MARK: - Parse

    /// Reads a `call-p2p` message. Nil for anything that is not a well formed
    /// signal (wrong type, unknown signal, bad JSON, bad payload).
    public static func parse(_ stanza: XMPPStanza, now: Date = Date()) -> P2PSignal? {
        guard stanza.name == "message",
              let data = stanza.getChild("data"),
              (data.attributes["type"] ?? "").lowercased() == dataType else {
            return nil
        }
        let callId = CallSignaling.firstAttribute(data.attributes, keys: ["callId", "callid"]) ?? ""
        let rawSignal = (data.attributes["signal"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !callId.isEmpty, let name = P2PSignalName(rawValue: rawSignal) else { return nil }

        let payloadText = data.attributes["payload"] ?? "{}"
        guard let payloadData = payloadText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let payload = validatePayload(name, object) else {
            return nil
        }

        let from = (stanza.attributes["from"] ?? "")
            .split(separator: "/", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let fromBare = from.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let fromLocal = fromBare.split(separator: "@", omittingEmptySubsequences: false).first.map(String.init) ?? ""

        let age = stanzaAgeMs(stanza, now: now)
        return P2PSignal(
            callId: callId,
            name: name,
            payload: payload,
            fromBare: fromBare,
            fromLocal: fromLocal,
            ageMs: age,
            delayed: stanza.getChild("delay") != nil
        )
    }

    private static func validatePayload(_ name: P2PSignalName, _ p: [String: Any]) -> P2PSignalPayload? {
        switch name {
        case .offer, .answer:
            guard (p["type"] as? String) == name.rawValue,
                  let sdp = p["sdp"] as? String, !sdp.isEmpty, sdp.count <= maxSdpLength else {
                return nil
            }
            return .sdp(type: name.rawValue, sdp: sdp)
        case .candidate:
            guard let candidate = p["candidate"] as? String, candidate.count <= maxCandidateLength else {
                return nil
            }
            return .candidate(P2PCandidatePayload(
                candidate: candidate,
                sdpMid: p["sdpMid"] as? String,
                sdpMLineIndex: (p["sdpMLineIndex"] as? NSNumber)?.intValue,
                usernameFragment: p["usernameFragment"] as? String
            ))
        case .end:
            return .end(reason: (p["reason"] as? String).map { String($0.prefix(maxReasonLength)) })
        }
    }

    /// The server stamps a microsecond id on archived stanzas; the first 13
    /// digits are epoch ms.
    private static func stanzaAgeMs(_ stanza: XMPPStanza, now: Date) -> Int64? {
        let id = stanza.getChild("stanza-id")?.attributes["id"]
        guard let created = CallSignaling.extractNumericTimestamp(id) else { return nil }
        return abs(Int64(now.timeIntervalSince1970 * 1000) - created)
    }

    /// Whether a parsed signal belongs to a live negotiation. An `end` is
    /// always accepted unless replayed.
    public static func isFresh(_ signal: P2PSignal) -> Bool {
        if signal.delayed { return false }
        if signal.name == .end { return true }
        guard let age = signal.ageMs else { return true }
        return age <= maxSignalAgeMs
    }
}
