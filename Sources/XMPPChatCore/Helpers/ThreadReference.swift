//
//  ThreadReference.swift
//  XMPPChatCore
//
//  Thread and quote references. A reply carries the parent in its `mainMessage`
//  attribute as a JSON object (web createMainMessageForThread). Mirrors
//  parseMessageReference and createMainMessageForThread in the web SDK.
//

import Foundation

public enum ThreadReference {

    /// The parsed `mainMessage` JSON. Only the keys the UI reads are kept.
    public struct Parsed: Equatable {
        public let id: String?
        public let text: String?
        public let roomJid: String?
        public let userName: String?
        public let createdAt: String?
    }

    /// Parses a `mainMessage` attribute. Returns nil when the value is empty or
    /// not a JSON object (web parseMessageReference).
    public static func parse(_ raw: String?) -> Parsed? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return Parsed(
            id: stringValue(object["id"]),
            text: object["text"] as? String,
            roomJid: object["roomJid"] as? String,
            userName: object["userName"] as? String,
            createdAt: object["createdAt"] as? String
        )
    }

    /// Id of the message a reply belongs to, or nil for a plain message.
    public static func parentId(of message: Message) -> String? {
        parse(message.mainMessage)?.id
    }

    /// True when the message is a thread reply (web `isReply === 'true'`).
    public static func isThreadReply(_ message: Message) -> Bool {
        message.isReply == true
    }

    /// Parent id of the thread a main-list message opens. A reply that is also
    /// shown in the channel still opens its parent's thread (web handleReplyMessage).
    public static func threadParentId(of message: Message) -> String? {
        parentId(of: message)
    }

    /// Thread replies of `parentId` found in `messages`, oldest first
    /// (web ThreadWrapper replyCount and the thread filter).
    public static func threadReplies(of parentId: String, in messages: [Message]) -> [Message] {
        messages
            .filter { isThreadReply($0) && self.parentId(of: $0) == parentId }
            .sorted { ($0.timestamp ?? 0) < ($1.timestamp ?? 0) }
    }

    /// Replies grouped by parent id, for the root's reply pill (web MessageList
    /// `repliesByParentId`). Includes replies that are also shown in the channel.
    public static func repliesByParent(_ messages: [Message]) -> [String: [Message]] {
        var buckets: [String: [Message]] = [:]
        for message in messages {
            guard let parent = parentId(of: message) else { continue }
            buckets[parent, default: []].append(message)
        }
        return buckets
    }

    /// A stand-in for a parent that is not loaded, built from the reply's
    /// `mainMessage` JSON. Nil when the reply carries no parent id.
    public static func parentStub(for message: Message) -> Message? {
        guard let parsed = parse(message.mainMessage), let id = parsed.id, !id.isEmpty else {
            return nil
        }
        let name = parsed.userName ?? ""
        let user = User(
            id: name,
            name: name,
            firstName: nil,
            lastName: nil,
            profileImage: nil,
            xmppUsername: nil
        )
        let date = parsed.createdAt.flatMap { isoFormatter().date(from: $0) } ?? Date()
        return Message(
            id: id,
            user: user,
            date: date,
            body: parsed.text ?? "",
            roomJid: parsed.roomJid ?? message.roomJid
        )
    }

    /// The JSON placed in `mainMessage` when a reply is sent for `message`.
    /// Keys and value shapes match web `createMainMessageForThread`.
    public static func mainMessageJSON(for message: Message) -> String {
        let object: [String: Any] = [
            "text": message.body,
            "id": message.id,
            "userName": message.user.name,
            "createdAt": isoFormatter().string(from: message.date),
            "imageLocation": message.location ?? "",
            "imagePreview": message.locationPreview ?? "",
            "mimeType": message.mimetype ?? "",
            "size": "",
            "duration": "",
            "waveForm": "",
            "attachmentId": "",
            "wrappable": "",
            "nftActionType": "",
            "contractAddress": "",
            "roomJid": message.roomJid,
            "nftId": ""
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    // MARK: - Helpers

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    /// JavaScript `Date.prototype.toISOString` shape, e.g. 2026-10-16T12:00:00.000Z.
    private static func isoFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }
}
