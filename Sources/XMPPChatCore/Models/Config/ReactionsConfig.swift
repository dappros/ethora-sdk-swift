//
//  ReactionsConfig.swift
//  XMPPChatCore
//
//  Reaction and reply switches. The key names follow the RN SDK's IConfig
//  (`reactions.enabled`, `reactions.quickReactions`, `reactions.picker`,
//  `disableReactions`, `disableReplies`); the web SDK has no equivalent keys.
//

import Foundation

public struct ReactionsConfig: Codable, Equatable {
    /// `false` turns reactions off (same effect as `ChatConfig.disableReactions`).
    public var enabled: Bool?
    /// Shortcodes for the quick bar. The first 8 are used. Nil or empty means
    /// `EmojiShortcodes.defaultQuickReactions`.
    public var quickReactions: [String]?
    /// `false` hides the full picker and keeps only the quick bar.
    public var picker: Bool?

    public init(enabled: Bool? = nil, quickReactions: [String]? = nil, picker: Bool? = nil) {
        self.enabled = enabled
        self.quickReactions = quickReactions
        self.picker = picker
    }
}
