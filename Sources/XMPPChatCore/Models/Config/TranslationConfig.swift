//
//  TranslationConfig.swift
//  XMPPChatCore
//
//  `config.translates`, same keys as web and RN. Plain data is Codable and
//  persisted; host callbacks (`onTranslate`, `showTranslateForMessage`) live
//  on the struct but are never encoded.
//

import Foundation

public enum Iso639_1Code: String, Codable {
    case en = "en"
    case es = "es"
    case fr = "fr"
    case pt = "pt"
    case ht = "ht"
    case zh = "zh"
}

/// `auto` shows a translation inline. `manual` shows a "Translate" link first.
public enum TranslateMode: String, Codable, Equatable {
    case auto
    case manual
}

/// Host translator. Receives the text, its source language (base or regional),
/// the reader's full locale and the message. Return nil to fall back to the
/// translation that arrived with the message.
public typealias TranslateHandler = (
    _ text: String,
    _ sourceLocale: String?,
    _ targetLocale: String,
    _ message: Message
) async throws -> String?

public struct TranslationsConfig: Codable, Equatable {
    public var enabled: Bool
    public var translations: Iso639_1Code?
    /// Default display mode. The reader can change it unless `forceType` is set.
    public var mode: TranslateMode?
    /// Pins `mode` as host policy. Hides the auto/manual switch.
    public var forceType: Bool?
    /// Reader's full BCP-47 locale. Falls back to `i18n.locale`.
    public var readerLocale: String?
    /// Shows the globe button in the chat header. Defaults to true when enabled.
    public var showLanguageSelector: Bool?
    /// Shows the language list inside the globe sheet. Defaults to true.
    public var showLanguageList: Bool?
    /// Opt-in built-in translate service for manual mode. Never derived from baseUrl.
    public var endpoint: String?
    /// Host translator. Wins over `endpoint` and the attached translations.
    public var onTranslate: TranslateHandler?
    /// Host predicate that decides whether a message gets a Translate action.
    public var showTranslateForMessage: ((Message) -> Bool)?

    public init(
        enabled: Bool,
        translations: Iso639_1Code? = nil,
        mode: TranslateMode? = nil,
        forceType: Bool? = nil,
        readerLocale: String? = nil,
        showLanguageSelector: Bool? = nil,
        showLanguageList: Bool? = nil,
        endpoint: String? = nil,
        onTranslate: TranslateHandler? = nil,
        showTranslateForMessage: ((Message) -> Bool)? = nil
    ) {
        self.enabled = enabled
        self.translations = translations
        self.mode = mode
        self.forceType = forceType
        self.readerLocale = readerLocale
        self.showLanguageSelector = showLanguageSelector
        self.showLanguageList = showLanguageList
        self.endpoint = endpoint
        self.onTranslate = onTranslate
        self.showTranslateForMessage = showTranslateForMessage
    }

    // Equality and persistence cover the data fields only. Closures cannot be compared.
    public static func == (lhs: TranslationsConfig, rhs: TranslationsConfig) -> Bool {
        lhs.enabled == rhs.enabled
            && lhs.translations == rhs.translations
            && lhs.mode == rhs.mode
            && lhs.forceType == rhs.forceType
            && lhs.readerLocale == rhs.readerLocale
            && lhs.showLanguageSelector == rhs.showLanguageSelector
            && lhs.showLanguageList == rhs.showLanguageList
            && lhs.endpoint == rhs.endpoint
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, translations, mode, forceType, readerLocale
        case showLanguageSelector, showLanguageList, endpoint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try container.decode(Bool.self, forKey: .enabled)
        self.translations = try container.decodeIfPresent(Iso639_1Code.self, forKey: .translations)
        self.mode = try container.decodeIfPresent(TranslateMode.self, forKey: .mode)
        self.forceType = try container.decodeIfPresent(Bool.self, forKey: .forceType)
        self.readerLocale = try container.decodeIfPresent(String.self, forKey: .readerLocale)
        self.showLanguageSelector = try container.decodeIfPresent(Bool.self, forKey: .showLanguageSelector)
        self.showLanguageList = try container.decodeIfPresent(Bool.self, forKey: .showLanguageList)
        self.endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint)
        self.onTranslate = nil
        self.showTranslateForMessage = nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encodeIfPresent(translations, forKey: .translations)
        try container.encodeIfPresent(mode, forKey: .mode)
        try container.encodeIfPresent(forceType, forKey: .forceType)
        try container.encodeIfPresent(readerLocale, forKey: .readerLocale)
        try container.encodeIfPresent(showLanguageSelector, forKey: .showLanguageSelector)
        try container.encodeIfPresent(showLanguageList, forKey: .showLanguageList)
        try container.encodeIfPresent(endpoint, forKey: .endpoint)
    }
}
