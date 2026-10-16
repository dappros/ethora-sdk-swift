//
//  LanguagePreferences.swift
//  XMPPChatCore
//
//  The reader's language state: interface language (appLanguage), chat language
//  (chatLanguage, the language messages are translated into and the language
//  declared on the user's own messages), the "Translate my messages" switch and
//  the auto/manual display choice. Kept on the device, and the profile values
//  are applied when a session starts (web and RN keep the same two fields).
//

import Foundation
import Combine

@MainActor
public final class LanguagePreferences: ObservableObject {
    public static let shared = LanguagePreferences()

    /// The interface language (`appLanguage`), BCP-47.
    @Published public private(set) var uiLocale: String?
    /// The chat language (`chatLanguage`), BCP-47.
    @Published public private(set) var chatLanguage: String?
    /// Reader's "Translate my messages" switch. nil means never touched (on).
    @Published public private(set) var translateSendEnabled: Bool?
    /// The reader's own auto/manual pick. Ignored when the host forces a mode.
    @Published public private(set) var readerMode: TranslateMode?

    private let defaults = UserDefaults.standard
    private enum Key {
        static let uiLocale = "ethora_ui_locale"
        static let chatLanguage = "ethora_chat_language"
        static let translateSend = "ethora_translate_send_enabled"
        static let readerMode = "ethora_translate_reader_mode"
    }

    private init() {
        uiLocale = defaults.string(forKey: Key.uiLocale)
        chatLanguage = defaults.string(forKey: Key.chatLanguage)
        if defaults.object(forKey: Key.translateSend) != nil {
            translateSendEnabled = defaults.bool(forKey: Key.translateSend)
        }
        if let raw = defaults.string(forKey: Key.readerMode) {
            readerMode = TranslateMode(rawValue: raw)
        }
    }

    // MARK: - Resolution

    /// Captions follow the host's `i18n.locale` when it is set, otherwise the
    /// reader's interface language.
    public var effectiveUILocale: String? {
        ConfigStore.shared.config.i18n?.locale ?? uiLocale
    }

    /// The locale translations are rendered into: the host's
    /// `translates.readerLocale`, then `i18n.locale`, then the reader's choices.
    public var readerLocale: String {
        let config = ConfigStore.shared.config
        return config.translates?.readerLocale
            ?? config.i18n?.locale
            ?? chatLanguage
            ?? uiLocale
            ?? UIStrings.defaultLanguage
    }

    /// The language declared on outgoing messages (`<translate source>`).
    public var senderLanguage: String {
        chatLanguage ?? uiLocale ?? UIStrings.defaultLanguage
    }

    /// The `<translate source>` for an outgoing message, or nil when the text goes
    /// out untagged (translation off, or the reader turned "Translate my messages" off).
    public var outgoingTranslateSource: String? {
        let enabled = ConfigStore.shared.config.translates?.enabled == true
        guard MessageTranslationResolver.shouldTagOutgoingSource(
            translatesEnabled: enabled,
            translateSendEnabled: translateSendEnabled
        ) else { return nil }
        return UIStrings.baseLanguage(senderLanguage)
    }

    // MARK: - Local choices

    public func setUILocale(_ locale: String?) {
        uiLocale = locale
        defaults.set(locale, forKey: Key.uiLocale)
    }

    public func setChatLanguage(_ locale: String?) {
        chatLanguage = locale
        defaults.set(locale, forKey: Key.chatLanguage)
    }

    public func setTranslateSendEnabled(_ enabled: Bool) {
        translateSendEnabled = enabled
        defaults.set(enabled, forKey: Key.translateSend)
    }

    public func setReaderMode(_ mode: TranslateMode?) {
        readerMode = mode
        defaults.set(mode?.rawValue, forKey: Key.readerMode)
    }

    // MARK: - Profile

    /// Applies the profile's languages when a session starts. An unset
    /// `chatLanguage` follows `appLanguage`, the backend's own rule.
    public func applyProfile(_ user: User?, config: ChatConfig? = nil) {
        guard let user = user, (config ?? ConfigStore.shared.config).settings?.languages?.enabled == true else {
            return
        }
        if let app = LanguageTag.canonical(user.appLanguage), app != uiLocale {
            setUILocale(app)
        }
        if let chat = LanguageTag.canonical(user.chatLanguage) ?? LanguageTag.canonical(user.appLanguage),
           chat != chatLanguage {
            setChatLanguage(chat)
        }
    }

    /// Chooses the interface language. The profile write runs behind the choice
    /// and never reverts it when the network fails.
    public func chooseAppLanguage(_ id: String) async -> Bool {
        guard let locale = LanguageTag.canonical(id) else { return false }
        setUILocale(locale)
        guard languagesEnabled else { return true }
        return await AccountAPI.updateProfileLanguage(field: .appLanguage, value: locale)
    }

    /// Chooses the language messages are translated into. Same write-behind rule.
    public func chooseChatLanguage(_ id: String) async -> Bool {
        guard let locale = LanguageTag.canonical(id) else { return false }
        setChatLanguage(locale)
        guard languagesEnabled else { return true }
        return await AccountAPI.updateProfileLanguage(field: .chatLanguage, value: locale)
    }

    public var languagesEnabled: Bool {
        ConfigStore.shared.config.settings?.languages?.enabled == true
    }
}

/// BCP-47 canonicalisation for the language fields: "en-ca" -> "en-CA".
public enum LanguageTag {
    public static func canonical(_ value: String?) -> String? {
        let raw = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = raw.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
        guard let language = parts.first,
              (2...3).contains(language.count),
              language.allSatisfy({ $0.isASCII && $0.isLetter }),
              parts.count <= 2 else { return nil }
        let base = language.lowercased()
        guard parts.count == 2, let region = parts.last, !region.isEmpty else { return base }
        let formattedRegion = region.count == 2 ? region.uppercased() : region
        return "\(base)-\(formattedRegion)"
    }

    /// Display name for a language tag: the host's option label, else the
    /// language's own name for itself.
    public static func label(for id: String) -> String {
        if let known = defaultOptions.first(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) {
            return known.name
        }
        let base = id.split(separator: "-").first.map { String($0).lowercased() } ?? id
        return autonyms[base] ?? id
    }

    /// The built-in offer list (en-CA, es-US, fr-CA), as RN ships it.
    public static let defaultOptions: [(id: String, name: String)] = [
        ("en-CA", "English"),
        ("es-US", "Español"),
        ("fr-CA", "Français"),
    ]

    private static let autonyms: [String: String] = [
        "en": "English", "es": "Español", "fr": "Français", "pt": "Português",
        "ht": "Kreyòl ayisyen", "zh": "中文", "de": "Deutsch", "it": "Italiano",
        "uk": "Українська", "ru": "Русский", "pl": "Polski", "tr": "Türkçe",
        "ar": "العربية", "hi": "हिन्दी", "ja": "日本語", "ko": "한국어",
        "nl": "Nederlands", "sv": "Svenska",
    ]
}
