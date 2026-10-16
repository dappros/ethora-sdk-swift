//
//  MessageSearch.swift
//  XMPPChatCore
//
//  Message search models, query building, response parsing and the opt-in gate.
//  Translated from src/networking/api-requests/messageSearch.api.ts,
//  src/components/Modals/MessageSearchModal/searchFilters.ts and
//  src/helpers/isMessageSearchEnabled.ts
//

import Foundation

// MARK: - Models

/// One archived message returned by `GET /v2/apps/{appId}/messages/search`.
public struct MessageSearchHit: Equatable, Sendable, Identifiable {
    /// The archive row's own id. Empty on some old rows, see `key`.
    public let id: String
    /// Room name (local part of the room JID).
    public let chatId: String
    public let chatType: String
    /// Full room JID.
    public let room: String
    /// Sender's full JID, with the xmpp host: `appId_userId@xmpp.host`.
    public let from: String
    public let fromUserId: String
    public let body: String
    public let messageId: String
    public let stanzaId: String
    public let createdAt: String

    public init(
        id: String,
        chatId: String,
        chatType: String,
        room: String,
        from: String,
        fromUserId: String,
        body: String,
        messageId: String,
        stanzaId: String,
        createdAt: String
    ) {
        self.id = id
        self.chatId = chatId
        self.chatType = chatType
        self.room = room
        self.from = from
        self.fromUserId = fromUserId
        self.body = body
        self.messageId = messageId
        self.stanzaId = stanzaId
        self.createdAt = createdAt
    }

    /// Unique per hit. `stanzaId` and `messageId` are NOT unique: old archive
    /// pages come back with both empty, which made every key `chatId:` and
    /// made a duplicate check by those ids drop real hits.
    public var key: String {
        if !id.isEmpty { return id }
        return "\(chatId):\(stanzaId):\(messageId):\(createdAt):\(String(body.prefix(24)))"
    }

    /// `createdAt` as a date, when the server sent a parseable ISO 8601 value.
    public var createdDate: Date? {
        MessageSearchDates.parseISO(createdAt)
    }
}

/// One page of search results.
public struct MessageSearchPage: Equatable, Sendable {
    public let items: [MessageSearchHit]
    /// Total matches on the server, not the size of this page.
    public let total: Int
    public let offset: Int
    public let limit: Int
    /// Where the next page starts, counted in SERVER rows. Deleted and empty
    /// rows are dropped from `items`, and paging by the filtered count would
    /// request rows that were already seen.
    public let nextOffset: Int

    public init(items: [MessageSearchHit], total: Int, offset: Int, limit: Int, nextOffset: Int) {
        self.items = items
        self.total = total
        self.offset = offset
        self.limit = limit
        self.nextOffset = nextOffset
    }

    public var hasMore: Bool { nextOffset < total }
}

/// Parameters of one search request.
public struct MessageSearchQuery: Equatable, Sendable {
    public static let pageSize = 20
    /// Minimum query length, in trimmed characters (web `MIN_QUERY_LENGTH`).
    public static let minQueryLength = 2

    public var q: String
    /// Room name. `nil` searches every visible chat.
    public var chatId: String?
    /// Only messages from this member (`_id` of the room member).
    public var fromUserId: String?
    /// ISO 8601 bounds. The server rejects anything else.
    public var since: String?
    public var until: String?
    public var limit: Int
    public var offset: Int

    public init(
        q: String,
        chatId: String? = nil,
        fromUserId: String? = nil,
        since: String? = nil,
        until: String? = nil,
        limit: Int = MessageSearchQuery.pageSize,
        offset: Int = 0
    ) {
        self.q = q
        self.chatId = chatId
        self.fromUserId = fromUserId
        self.since = since
        self.until = until
        self.limit = limit
        self.offset = offset
    }

    /// The query string, in the same parameter set web sends. Empty optional
    /// parameters are left out.
    public var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if let chatId, !chatId.isEmpty { items.append(URLQueryItem(name: "chatId", value: chatId)) }
        if let fromUserId, !fromUserId.isEmpty { items.append(URLQueryItem(name: "fromUserId", value: fromUserId)) }
        if let since, !since.isEmpty { items.append(URLQueryItem(name: "since", value: since)) }
        if let until, !until.isEmpty { items.append(URLQueryItem(name: "until", value: until)) }
        return items
    }
}

// MARK: - Parsing

public enum MessageSearchParser {
    /// Parses a search response body. Mirrors `searchMessages` in
    /// messageSearch.api.ts: rows with `deletedAt` set (a deleted message is
    /// still archived) and rows without a body are dropped, and `nextOffset`
    /// counts the server rows, not the kept ones.
    public static func parsePage(data: Data, offset: Int, limit: Int) throws -> MessageSearchPage {
        let root = try JSONSerialization.jsonObject(with: data, options: [])
        let object = root as? [String: Any] ?? [:]
        return parsePage(object: object, offset: offset, limit: limit)
    }

    public static func parsePage(object: [String: Any], offset: Int, limit: Int) -> MessageSearchPage {
        let rawRows = object["items"] as? [[String: Any]] ?? []

        let items: [MessageSearchHit] = rawRows.compactMap { row in
            if isTruthy(row["deletedAt"]) { return nil }
            guard let body = row["body"] as? String, !body.isEmpty else { return nil }
            return MessageSearchHit(
                id: string(row["_id"]),
                chatId: string(row["chatId"]),
                chatType: string(row["chatType"]),
                room: string(row["room"]),
                from: string(row["from"]),
                fromUserId: string(row["fromUserId"]),
                body: body,
                messageId: string(row["messageId"]),
                stanzaId: string(row["stanzaId"]),
                createdAt: string(row["createdAt"])
            )
        }

        let total = int(object["total"]) ?? 0
        let serverOffset = int(object["offset"]) ?? offset
        let serverLimit = int(object["limit"]) ?? limit
        return MessageSearchPage(
            items: items,
            total: total,
            offset: serverOffset,
            limit: serverLimit,
            nextOffset: offset + rawRows.count
        )
    }

    /// JavaScript-style truthiness for the fields the server may leave as null.
    private static func isTruthy(_ value: Any?) -> Bool {
        switch value {
        case nil, is NSNull: return false
        case let string as String: return !string.isEmpty
        case let number as NSNumber: return number.doubleValue != 0
        default: return true
        }
    }

    private static func string(_ value: Any?) -> String {
        switch value {
        case let string as String: return string
        case let number as NSNumber: return number.stringValue
        default: return ""
        }
    }

    private static func int(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber: return number.intValue
        case let string as String: return Int(string)
        default: return nil
        }
    }
}

// MARK: - Dates

/// Date filter helpers. A picked day is turned into the start and the end of
/// that day in the reader's time zone, as web does (searchFilters.ts).
public enum MessageSearchDates {
    /// `2026-07-14` -> that day's first instant, in the reader's time zone.
    public static func dayStartISO(_ day: String, calendar: Calendar = .current) -> String? {
        dayBoundary(day, hour: 0, minute: 0, second: 0, nanosecond: 0, calendar: calendar)
    }

    /// The day's LAST instant. The server reads a bare date in `until` as the
    /// start of that day, which silently excludes the whole picked day.
    public static func dayEndISO(_ day: String, calendar: Calendar = .current) -> String? {
        dayBoundary(day, hour: 23, minute: 59, second: 59, nanosecond: 999_000_000, calendar: calendar)
    }

    /// True when both days are set and the range runs backwards.
    public static func isBackwardsRange(from: String, to: String) -> Bool {
        !from.isEmpty && !to.isEmpty && from > to
    }

    /// Strict `yyyy-MM-dd` check (no roll-over: 2026-02-30 is not a day).
    public static func isValidDay(_ day: String) -> Bool {
        dayComponents(day) != nil
    }

    static func parseISO(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }

    /// The ISO form web sends (`toISOString`): UTC, milliseconds, `Z`.
    public static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    private static func dayComponents(_ day: String) -> (year: Int, month: Int, day: Int)? {
        let parts = day.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let dayOfMonth = Int(parts[2]) else {
            return nil
        }
        return (year, month, dayOfMonth)
    }

    private static func dayBoundary(
        _ day: String,
        hour: Int,
        minute: Int,
        second: Int,
        nanosecond: Int,
        calendar: Calendar
    ) -> String? {
        guard let parts = dayComponents(day) else { return nil }
        var components = DateComponents()
        components.year = parts.year
        components.month = parts.month
        components.day = parts.day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.nanosecond = nanosecond
        guard let date = calendar.date(from: components) else { return nil }
        // Reject roll-overs such as 2026-02-30 -> 2026-03-02.
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == parts.year, check.month == parts.month, check.day == parts.day else { return nil }
        return isoString(date)
    }
}

// MARK: - Gate

/// The single rule for message search. It is opt-in: the host must set
/// `enableMessageSearch` AND provide an `appId`, because the archive endpoint
/// is scoped by app. A leftover `disableMessageSearch: true` still wins as a
/// hard off. Every entry point goes through this check.
public enum MessageSearchGate {
    public static func isEnabled(_ config: ChatConfig?) -> Bool {
        guard let config else { return false }
        let appId = config.appId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return config.enableMessageSearch == true
            && config.disableMessageSearch != true
            && !appId.isEmpty
    }

    /// The header search button is shown when search is on and the host has
    /// not hidden only the header button (`chatHeaderSettings.hideSearch`).
    public static func isHeaderButtonVisible(_ config: ChatConfig?) -> Bool {
        isEnabled(config) && config?.chatHeaderSettings?.hideSearch != true
    }
}
