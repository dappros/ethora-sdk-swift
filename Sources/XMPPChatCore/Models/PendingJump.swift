//
//  PendingJump.swift
//  XMPPChatCore
//
//  A request to bring one archived message on screen. Translated from the
//  `requestJumpToMessage` action of roomsSlice.ts.
//

import Foundation

public struct PendingJump: Equatable {
    /// How long a request stays alive. A request that is never fulfilled must
    /// not fire at some unrelated later moment (web `JUMP_TTL_MS`).
    public static let ttl: TimeInterval = 60

    public let roomJID: String
    /// Every id the caller knows the message by: archive id, stanza id,
    /// message id, or the client xmpp id. Blanks and duplicates are removed.
    public let ids: [String]
    /// Time and body of the message, used when no id matches.
    public let createdAt: Date?
    public let body: String?
    /// When the request was made.
    public let requestedAt: Date

    public init(
        roomJID: String,
        ids: [String],
        createdAt: Date? = nil,
        body: String? = nil,
        requestedAt: Date = Date()
    ) {
        self.roomJID = roomJID
        self.ids = PendingJump.uniqueIds(ids)
        self.createdAt = createdAt
        self.body = body
        self.requestedAt = requestedAt
    }

    public func isExpired(now: Date = Date()) -> Bool {
        now.timeIntervalSince(requestedAt) > PendingJump.ttl
    }

    public static func uniqueIds(_ candidates: [String]) -> [String] {
        var seen: [String] = []
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !seen.contains(trimmed) {
                seen.append(trimmed)
            }
        }
        return seen
    }
}
