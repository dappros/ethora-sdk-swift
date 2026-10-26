//
//  MessageReactions.swift
//  XMPPChatCore
//
//  Pure reaction-map updates shared by the live handler, MAM replay, the
//  optimistic local write and the pending-target buffer. Mirrors the web
//  reducer `setReactions` (roomsSlice.ts): keyed by reactor localpart, an
//  empty emoji list removes the reactor, and the newest update wins.
//

import Foundation

public enum MessageReactions {

    /// One reactor's reaction as shown in the UI.
    public struct Summary: Equatable {
        /// Shortcode, for example "+1" or "heart".
        public let shortcode: String
        /// Reactor localparts that currently have this shortcode, in order.
        public let reactorKeys: [String]
        /// Display names for the same reactors, in the same order.
        public let reactorNames: [String]

        public var count: Int { reactorKeys.count }
    }

    /// Reactor key: localpart of the reactor JID (web `from.split('@')[0]`).
    public static func reactorKey(fromJID jid: String) -> String {
        jid.components(separatedBy: "@").first ?? jid
    }

    /// Applies one reactor's full shortcode set. An empty `emoji` records a
    /// removal. An update older than the stored one for the same reactor is
    /// ignored. Keys that would pollute an object map are rejected like web.
    public static func apply(
        _ map: [String: ReactionMessage]?,
        reactorKey: String,
        emoji: [String],
        data: [String: String],
        timestamp: Int64?
    ) -> [String: ReactionMessage]? {
        guard !reactorKey.isEmpty,
              reactorKey != "__proto__",
              reactorKey != "constructor",
              reactorKey != "prototype" else {
            return map
        }
        var result = map ?? [:]
        if let stored = result[reactorKey]?.timestamp,
           let incoming = timestamp,
           stored > incoming {
            return map
        }
        if emoji.isEmpty, result[reactorKey] == nil {
            // Removal for a reactor we never saw: nothing to record.
            return map
        }
        result[reactorKey] = ReactionMessage(emoji: emoji, data: data, timestamp: timestamp)
        return result
    }

    /// Shortcodes a given reactor currently has on a message.
    public static func emoji(for reactorKey: String, in map: [String: ReactionMessage]?) -> [String] {
        map?[reactorKey]?.emoji ?? []
    }

    /// Chips for the bubble: one entry per shortcode, in order of first
    /// reaction. Removal markers (empty lists) are skipped.
    public static func summaries(_ map: [String: ReactionMessage]?) -> [Summary] {
        guard let map, !map.isEmpty else { return [] }

        let reactors = map
            .filter { !$0.value.emoji.isEmpty }
            .sorted { lhs, rhs in
                let l = lhs.value.timestamp ?? Int64.max
                let r = rhs.value.timestamp ?? Int64.max
                if l != r { return l < r }
                return lhs.key < rhs.key
            }

        var order: [String] = []
        var keysByEmoji: [String: [String]] = [:]
        var namesByEmoji: [String: [String]] = [:]
        for (key, reaction) in reactors {
            let name = displayName(for: reaction.data, fallback: key)
            for shortcode in reaction.emoji where !shortcode.isEmpty {
                if keysByEmoji[shortcode] == nil {
                    order.append(shortcode)
                    keysByEmoji[shortcode] = []
                    namesByEmoji[shortcode] = []
                }
                keysByEmoji[shortcode]?.append(key)
                namesByEmoji[shortcode]?.append(name)
            }
        }

        return order.map { shortcode in
            Summary(
                shortcode: shortcode,
                reactorKeys: keysByEmoji[shortcode] ?? [],
                reactorNames: namesByEmoji[shortcode] ?? []
            )
        }
    }

    /// Full name from the `<data senderFirstName senderLastName/>` attributes,
    /// falling back to the reactor key when neither is present.
    public static func displayName(for data: [String: String], fallback: String) -> String {
        let first = data["senderFirstName"] ?? ""
        let last = data["senderLastName"] ?? ""
        let joined = "\(first) \(last)".trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? fallback : joined
    }
}
