//
//  MamPaging.swift
//  XMPPChatCore
//
//  MAM (XEP-0313) paging primitives: archive ids, the <fin> answer, the cursor
//  rules and the query stanza. Translated from src/networking/xmpp/historyCursor.ts,
//  src/networking/xmpp/getHistory.xmpp.ts and xmppClient.ts requestMamHistory.
//

import Foundation

public enum MamCursor {
    /// Archive ids are microsecond timestamps (16 digits). web `isArchiveCursor`
    /// requires a value above 1e14, so a millisecond timestamp is never mistaken
    /// for one.
    public static let archiveThreshold: Int64 = 100_000_000_000_000

    public static let namespace = "urn:xmpp:mam:2"

    public static func isArchiveCursor(_ value: Int64?) -> Bool {
        guard let value else { return false }
        return value > archiveThreshold
    }

    /// The `<fin>` that closes one MAM answer.
    public struct Fin: Equatable, Sendable {
        /// `complete="true"`: there is nothing older than this page.
        public let complete: Bool
        /// RSM `<first>`: the oldest archive row the server returned. This is
        /// the next paging cursor. It is set even for a page that displays no
        /// message (only reactions, receipts or deleted rows).
        public let first: Int64?
        /// RSM `<last>`: the newest archive row returned.
        public let last: Int64?

        public init(complete: Bool, first: Int64?, last: Int64?) {
            self.complete = complete
            self.first = first
            self.last = last
        }
    }

    /// Reads the `<fin>` of a MAM result iq. Returns nil for any other stanza.
    public static func parseFin(_ iq: XMPPStanza) -> Fin? {
        guard let fin = iq.getChild("fin", xmlns: namespace) ?? iq.getChild("fin") else {
            return nil
        }
        let complete: Bool = {
            let raw = fin.attributes["complete"]?.lowercased() ?? ""
            return raw == "true" || raw == "1"
        }()
        let set = fin.getChild("set")
        return Fin(
            complete: complete,
            first: archiveValue(set?.getChild("first")?.text),
            last: archiveValue(set?.getChild("last")?.text)
        )
    }

    /// The cursor after one page. `before` is the cursor the page was asked
    /// with (nil for a latest page). Rules, from web `applyHistoryPageCursor`:
    ///  - an older page moves the cursor back, never forward;
    ///  - a latest page sets the cursor only when the room had no messages, so a
    ///    late latest page never pulls an older cursor forward;
    ///  - a page without an archive `<first>` leaves the cursor where it was.
    public static func nextCursor(
        current: Int64?,
        before: Int64?,
        fin: Fin,
        hadMessages: Bool
    ) -> Int64? {
        guard let first = fin.first, isArchiveCursor(first) else { return current }
        if let before {
            let reference = current ?? before
            return first < reference ? first : current
        }
        if !hadMessages { return first }
        return current
    }

    /// Archive id of a message as a number, or nil when it is not one (a UUID
    /// or an xmpp id). Only archive ids are valid MAM cursors.
    public static func archiveId(_ raw: String?) -> Int64? {
        guard let raw, let value = Int64(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              isArchiveCursor(value) else { return nil }
        return value
    }

    private static func archiveValue(_ raw: String?) -> Int64? {
        guard let raw else { return nil }
        return Int64(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// One MAM page query. Wire shape matches web `requestMamHistory`.
public struct MamQuery: Equatable {
    public var chatJID: String
    public var queryId: String
    public var max: Int
    /// Exclusive upper bound: the rows strictly older than this id.
    public var before: Int64?
    /// Exclusive lower bound: the rows strictly newer than this id.
    public var after: Int64?
    /// ISO 8601 time filter (sent as a data form). Used to find a message that
    /// has no archive id.
    public var start: String?
    public var end: String?
    /// A latest page: `<before/>` with no value, which the server answers with
    /// the newest rows.
    public var latest: Bool

    public init(
        chatJID: String,
        queryId: String,
        max: Int,
        before: Int64? = nil,
        after: Int64? = nil,
        start: String? = nil,
        end: String? = nil
    ) {
        self.chatJID = chatJID
        self.queryId = queryId
        self.max = max
        self.before = before
        self.after = after
        self.start = start
        self.end = end
        self.latest = before == nil && after == nil && start == nil && end == nil
    }

    /// The iq. Element order and attributes follow web `requestMamHistory`:
    /// no `<before>` when a window or time query is sent, `<before/>` (empty)
    /// for a latest page.
    public func stanza() -> XMPPStanza {
        var children: [XMPPStanza] = []
        if start != nil || end != nil {
            var fields: [XMPPStanza] = [
                XMPPStanza(name: "field", attributes: ["var": "FORM_TYPE", "type": "hidden"], children: [
                    XMPPStanza(name: "value", text: MamCursor.namespace),
                ]),
            ]
            if let start {
                fields.append(XMPPStanza(name: "field", attributes: ["var": "start"], children: [
                    XMPPStanza(name: "value", text: start),
                ]))
            }
            if let end {
                fields.append(XMPPStanza(name: "field", attributes: ["var": "end"], children: [
                    XMPPStanza(name: "value", text: end),
                ]))
            }
            children.append(XMPPStanza(
                name: "x",
                attributes: ["xmlns": "jabber:x:data", "type": "submit"],
                children: fields
            ))
        }

        var rsm: [XMPPStanza] = [XMPPStanza(name: "max", text: String(max))]
        if let after {
            rsm.append(XMPPStanza(name: "after", text: String(after)))
        } else if let before {
            rsm.append(XMPPStanza(name: "before", text: String(before)))
        } else if start == nil && end == nil {
            rsm.append(XMPPStanza(name: "before"))
        }
        children.append(XMPPStanza(
            name: "set",
            attributes: ["xmlns": "http://jabber.org/protocol/rsm"],
            children: rsm
        ))

        let query = XMPPStanza(
            name: "query",
            attributes: ["xmlns": MamCursor.namespace, "queryid": queryId],
            children: children
        )
        return XMPPStanza(
            name: "iq",
            attributes: ["type": "set", "to": chatJID, "id": queryId],
            children: [query]
        )
    }
}
