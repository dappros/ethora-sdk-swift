//
//  CallMode.swift
//  XMPPChatCore
//
//  Pure helpers that decide HOW a call is carried and how its call-token
//  attributes are read. Mirrors src/calls/callMode.ts, callDisplay.ts and
//  senderTrust.ts on the web SDK. No state and no I/O.
//
//  Three kinds of call exist: 1:1 over a peer connection ("p2p", chosen by the
//  server), 1:1 over LiveKit (fallback) and group over LiveKit. The client
//  never picks the transport, it follows the server's `mode`.
//

import Foundation

public enum CallMode: String, Equatable, Sendable {
    case livekit
    case p2p
}

/// A STUN/TURN entry of a call's ICE configuration (serializable subset of
/// RTCIceServer).
public struct IceServerConfig: Equatable, Sendable {
    public var urls: [String]
    public var username: String?
    public var credential: String?

    public init(urls: [String], username: String? = nil, credential: String? = nil) {
        self.urls = urls
        self.username = username
        self.credential = credential
    }
}

/// Attributes of a `<data type="call-token">` element, defensively read.
public struct ParsedCallTokenAttrs: Equatable, Sendable {
    public var token: String
    public var room: String
    public var callId: String?
    /// Valid `kind` attribute, nil when absent or unrecognised.
    public var kind: CallKind?
    public var mode: CallMode
    public var group: Bool
    /// Callee's ICE servers for `mode=p2p`, nil when absent or unparseable.
    public var iceServers: [IceServerConfig]?
    /// Public LiveKit URL for `mode=livekit`, nil when absent or unusable.
    public var livekitUrl: String?
    /// Caller display name as plain text; "" when absent. Trustworthy only from
    /// the system account.
    public var callerName: String
    /// Caller's xmppUsername when well formed. Same trust rule.
    public var caller: String?
}

public enum CallModeParsing {
    // MARK: - Attribute reading

    /// Tolerant reader for the call-token stanza. A server that sends neither
    /// `mode` nor `group` (every server before P2P / group calls) yields
    /// `mode: .livekit`, `group: false`, i.e. the legacy behaviour.
    public static func parseCallTokenAttrs(_ attrs: [String: String]) -> ParsedCallTokenAttrs {
        let kindRaw = trimmed(attrs["kind"]).lowercased()
        let mode: CallMode = trimmed(attrs["mode"]).lowercased() == "p2p" ? .p2p : .livekit
        let iceList = mode == .p2p ? normalizeIceServers(json: attrs["ice"]) : []
        let callId = CallSignaling.firstAttribute(attrs, keys: ["callId", "callid"])
        return ParsedCallTokenAttrs(
            token: trimmed(attrs["token"]),
            room: trimmed(attrs["room"]),
            callId: callId,
            kind: CallKind(rawValue: kindRaw),
            mode: mode,
            // A p2p call is 1:1 by construction; never let a stray attribute flip it.
            group: mode == .livekit && isTrueish(attrs["group"]),
            iceServers: mode == .p2p && !iceList.isEmpty ? iceList : nil,
            livekitUrl: mode == .livekit ? normalizeLivekitUrl(attrs["livekitUrl"]) : nil,
            callerName: sanitizeCallName(attrs["callerName"]),
            caller: sanitizeXmppUsername(attrs["caller"])
        )
    }

    public static func isTrueish(_ value: String?) -> Bool {
        let text = trimmed(value).lowercased()
        return text == "true" || text == "1"
    }

    private static func trimmed(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A LiveKit server URL as the backend publishes it. Only ws/wss/http/https
    /// URLs are accepted: the value becomes the connect target of the media
    /// session, so anything else is treated as unset.
    public static func normalizeLivekitUrl(_ raw: String?) -> String? {
        let text = trimmed(raw)
        guard text.range(of: #"^(wss?|https?)://[^\s]+$"#, options: [.regularExpression, .caseInsensitive]) != nil else {
            return nil
        }
        return text
    }

    // MARK: - ICE servers

    /// Accepts a JSON string holding an array or an `{ "iceServers": [...] }`
    /// envelope and returns only well formed stun/turn entries. Anything else
    /// is dropped, never thrown.
    public static func normalizeIceServers(json raw: String?) -> [IceServerConfig] {
        let text = trimmed(raw)
        guard !text.isEmpty, let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        return normalizeIceServers(object: object)
    }

    public static func normalizeIceServers(object raw: Any?) -> [IceServerConfig] {
        var value = raw
        if let envelope = value as? [String: Any], let inner = envelope["iceServers"] as? [Any] {
            value = inner
        }
        guard let list = value as? [Any] else { return [] }

        var out: [IceServerConfig] = []
        for entry in list {
            guard let item = entry as? [String: Any] else { continue }
            let rawUrls = item["urls"] ?? item["url"]
            let candidates: [Any]
            if let many = rawUrls as? [Any] {
                candidates = many
            } else if let one = rawUrls {
                candidates = [one]
            } else {
                candidates = []
            }
            let urls = candidates
                .compactMap { $0 as? String }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.range(of: #"^(stun|stuns|turn|turns):"#, options: [.regularExpression, .caseInsensitive]) != nil }
            if urls.isEmpty { continue }
            let username = (item["username"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let credential = (item["credential"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            out.append(IceServerConfig(urls: urls, username: username, credential: credential))
        }
        return out
    }

    // MARK: - Display hygiene (callDisplay.ts)

    public static let maxCallNameLength = 80

    /// True for strings that are a chat's internal name or an id rather than
    /// something a person would be called.
    public static func looksLikeRawRoomName(_ value: String?) -> Bool {
        let text = trimmed(value)
        if text.isEmpty { return false }
        let hex24 = "[0-9a-fA-F]{24}"
        let userId = "\(hex24)_\(hex24)(?:@[A-Za-z0-9.]+)?"
        let patterns = [
            "^\(userId)(?:-\(userId))*$",
            "^\(hex24)_[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
            "^[0-9a-fA-F_-]{16,}$",
        ]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    /// Plain-text, display-safe name: control, bidi and zero-width characters
    /// stripped, whitespace collapsed, capped at 80 characters. "" when nothing
    /// usable is left or the value is a raw chat name / id.
    public static func sanitizeCallName(_ value: String?) -> String {
        guard let value else { return "" }
        let unwanted: (Unicode.Scalar) -> Bool = { scalar in
            let v = scalar.value
            return v <= 0x1F || (0x7F...0x9F).contains(v)
                || (0x200B...0x200F).contains(v) || (0x202A...0x202E).contains(v)
                || (0x2060...0x2064).contains(v) || (0x2066...0x2069).contains(v)
                || v == 0xFEFF
        }
        var scalars = String.UnicodeScalarView()
        for scalar in value.unicodeScalars {
            scalars.append(unwanted(scalar) ? " " : scalar)
        }
        let collapsed = String(scalars)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        if collapsed.isEmpty { return "" }
        let capped = String(collapsed.prefix(maxCallNameLength)).trimmingCharacters(in: .whitespaces)
        return looksLikeRawRoomName(capped) ? "" : capped
    }

    /// An xmppUsername from a stanza attribute, or nil when it is not shaped
    /// like one (only used for lookups and routing, never shown).
    public static func sanitizeXmppUsername(_ value: String?) -> String? {
        let text = trimmed(value)
        let local = String(text.split(separator: "/", omittingEmptySubsequences: false).first ?? "")
        return local.range(of: #"^[A-Za-z0-9_-]{1,128}(?:@[A-Za-z0-9.-]+)?$"#, options: .regularExpression) != nil
            ? local
            : nil
    }

    // MARK: - Sender trust (senderTrust.ts)

    /// True when `fromJid` is the app's system account (`<appId>_<appId>`, the
    /// 24 hex character app id twice). The resource is ignored. With an
    /// `expectedDomain` the sender must also be on that domain. A missing or
    /// malformed JID is never trusted.
    public static func isSystemAccountSender(_ fromJid: String?, expectedDomain: String? = nil) -> Bool {
        let from = trimmed(fromJid)
        if from.isEmpty { return false }
        let bare = String(from.split(separator: "/", omittingEmptySubsequences: false).first ?? "")
        let parts = bare.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return false }
        let local = String(parts[0])
        let domain = String(parts[1]).lowercased()

        let halves = local.split(separator: "_", omittingEmptySubsequences: false)
        guard halves.count == 2, halves[0] == halves[1],
              String(halves[0]).range(of: "^[0-9a-fA-F]{24}$", options: .regularExpression) != nil else {
            return false
        }
        let expected = trimmed(expectedDomain).lowercased()
        return expected.isEmpty || domain == expected
    }
}

// MARK: - Create response

/// Normalised `POST /chats/call/create/:chatName` response.
public struct CallCreateResult: Equatable, Sendable {
    public var callId: String?
    public var mode: CallMode
    public var kind: CallKind
    /// Server-reported group flag, nil when the server did not say.
    public var group: Bool?
    public var livekitUrl: String?
    public var iceServers: [IceServerConfig]
    public var ttlSeconds: Double?

    public init(
        callId: String? = nil,
        mode: CallMode = .livekit,
        kind: CallKind = .video,
        group: Bool? = nil,
        livekitUrl: String? = nil,
        iceServers: [IceServerConfig] = [],
        ttlSeconds: Double? = nil
    ) {
        self.callId = callId
        self.mode = mode
        self.kind = kind
        self.group = group
        self.livekitUrl = livekitUrl
        self.iceServers = iceServers
        self.ttlSeconds = ttlSeconds
    }
}

public enum CallCreateError: Error, LocalizedError {
    case missingCallId

    public var errorDescription: String? {
        "Call response is missing callId"
    }
}

extension CallModeParsing {
    /// Reads the create response. Old servers answer with no `mode`, which maps
    /// to `.livekit` (the caller then waits for its own call-token as before).
    /// A p2p answer without a callId is unusable and throws.
    public static func parseCallCreateResponse(_ data: Any?, fallbackKind: CallKind) throws -> CallCreateResult {
        let root = (data as? [String: Any]) ?? [:]
        let d: [String: Any]
        if let nested = root["result"] as? [String: Any], root["mode"] == nil {
            d = nested
        } else {
            d = root
        }
        let mode: CallMode = ((d["mode"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "p2p"
            ? .p2p : .livekit
        let kindRaw = ((d["kind"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let callIdRaw = ((d["callId"] as? String) ?? (d["callid"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let callId = callIdRaw.isEmpty ? nil : callIdRaw
        if mode == .p2p, callId == nil { throw CallCreateError.missingCallId }
        let ttl = (d["ttlSeconds"] as? NSNumber)?.doubleValue
        return CallCreateResult(
            callId: callId,
            mode: mode,
            kind: CallKind(rawValue: kindRaw) ?? fallbackKind,
            group: d["group"] as? Bool,
            livekitUrl: normalizeLivekitUrl(d["livekitUrl"] as? String),
            iceServers: mode == .p2p ? normalizeIceServers(object: d["iceServers"]) : [],
            ttlSeconds: (ttl ?? 0) > 0 ? ttl : nil
        )
    }
}

// MARK: - Incoming while busy

/// What to do with an incoming call-token while another call may be active
/// (mirrors `decideIncomingWhileBusy` in callMode.ts).
///  - accept:     nothing active, ring.
///  - duplicate:  same callId as the active call (server re-delivery), ignore.
///  - replace:    legacy LiveKit behaviour, kept for livekit-vs-livekit.
///  - glareYield: both dialled each other; the smaller callId wins on BOTH
///                ends and this is the loser: drop ours, ring for theirs.
///  - glareKeep:  same race, we hold the winning callId, ignore theirs.
///  - busy:       a different call is in progress, decline the newcomer.
public enum CallModeDecision: Equatable, Sendable {
    case accept
    case duplicate
    case replace
    case glareYield
    case glareKeep
    case busy

    public struct Snapshot: Equatable, Sendable {
        public var phase: CallPhase
        public var direction: CallDirection?
        public var mode: CallMode
        public var callId: String?
        public var roomBareName: String?

        public init(phase: CallPhase, direction: CallDirection?, mode: CallMode, callId: String?, roomBareName: String?) {
            self.phase = phase
            self.direction = direction
            self.mode = mode
            self.callId = callId
            self.roomBareName = roomBareName
        }
    }

    public static func incomingWhileBusy(
        current: Snapshot,
        incomingMode: CallMode,
        incomingCallId: String?,
        incomingRoomBareName: String?
    ) -> CallModeDecision {
        if current.phase == .idle { return .accept }
        if let id = incomingCallId, !id.isEmpty, current.callId == id { return .duplicate }
        if current.mode != .p2p && incomingMode != .p2p { return .replace }

        let sameRoom = (incomingRoomBareName ?? "").isEmpty == false
            && current.roomBareName == incomingRoomBareName
        if sameRoom,
           current.direction == .outgoing,
           current.phase == .requesting,
           incomingMode == .p2p, current.mode == .p2p,
           let currentId = current.callId, !currentId.isEmpty,
           let incomingId = incomingCallId, !incomingId.isEmpty {
            return incomingId < currentId ? .glareYield : .glareKeep
        }
        return .busy
    }
}
