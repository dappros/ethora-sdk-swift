//
//  CallModels.swift
//  XMPPChatCore
//
//  Value types for 1:1 calls. Mirrors src/roomStore/callSlice.ts and
//  src/helpers/callLogMessage.ts in the web SDK.
//

import Foundation

public enum CallKind: String, Codable, Equatable, Sendable {
    case audio
    case video
}

public enum CallPhase: String, Equatable, Sendable {
    case idle
    case requesting
    case ringingIncoming
    case connecting
    case inCall
    case error
}

public enum CallDirection: String, Codable, Equatable, Sendable {
    case outgoing
    case incoming
}

/// Terminal states sent in an outgoing `<data type="call-state" state="...">`.
public enum CallSignalState: String, Equatable, Sendable {
    case ended
    case declined
    case cancelled
    case rejected
}

/// Metadata of a call-log chat entry. The label is rendered from this at view
/// time (see `CallLogFormatter`), so it follows the viewer's own direction.
public struct CallLogMeta: Codable, Equatable, Sendable {
    public var callId: String
    public var durationMs: Int64
    public var kind: CallKind
    /// Localpart of the user who started the call, when known.
    public var callerXmppUsername: String?

    public init(
        callId: String,
        durationMs: Int64,
        kind: CallKind,
        callerXmppUsername: String?
    ) {
        self.callId = callId
        self.durationMs = max(0, durationMs)
        self.kind = kind
        self.callerXmppUsername = callerXmppUsername
    }

    /// Missed or unanswered calls have no duration.
    public var isMissed: Bool { durationMs == 0 }

    /// The viewer started the call when the caller localpart matches theirs.
    public func isOutgoing(selfXmppUsername: String) -> Bool {
        guard let caller = callerXmppUsername, !caller.isEmpty else { return false }
        return caller == CallSignaling.localPart(of: selfXmppUsername)
    }
}

public enum CallLogFormatter {
    /// "12 sec", "1 min", "1 min 5 sec". Matches `formatCallDuration` on web.
    public static func formatDuration(ms: Int64) -> String {
        let totalSeconds = max(0, Int64((Double(ms) / 1000).rounded()))
        if totalSeconds < 60 {
            return "\(totalSeconds) sec"
        }
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if seconds == 0 {
            return "\(minutes) min"
        }
        return "\(minutes) min \(seconds) sec"
    }

    /// Viewer-facing label, e.g. "Outgoing call · 12 sec", "No answer".
    public static func label(for meta: CallLogMeta, selfXmppUsername: String) -> String {
        let outgoing = meta.isOutgoing(selfXmppUsername: selfXmppUsername)
        if meta.durationMs > 0 {
            let direction = outgoing ? "Outgoing" : "Incoming"
            return "\(direction) call · \(formatDuration(ms: meta.durationMs))"
        }
        return outgoing ? "No answer" : "Missed call"
    }

    /// Non-empty body stored on the parsed message. Chat pipelines drop
    /// messages with an empty body, and previews read it. The row itself is
    /// drawn from `CallLogMeta`, not from this text.
    public static func fallbackBody(for meta: CallLogMeta) -> String {
        meta.durationMs > 0
            ? "Call · \(formatDuration(ms: meta.durationMs))"
            : "Missed call"
    }
}
