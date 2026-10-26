//
//  LocalizationConfig.swift
//  XMPPChatCore
//
//  Config for interface captions (`i18n`) and the account settings screen
//  (`settings`: languages and change password). Same key names as RN/web.
//

import Foundation

/// Static UI captions. `locale` is a BCP-47 tag ("fr-CA"); captions resolve to
/// its base language. `strings` overrides or extends any built-in key.
public struct I18nConfig: Codable, Equatable {
    public var locale: String?
    public var strings: [String: String]?

    public init(locale: String? = nil, strings: [String: String]? = nil) {
        self.locale = locale
        self.strings = strings
    }
}

/// Switches for the account settings screen. Both are off by default.
public struct AccountSettingsConfig: Codable, Equatable {
    public var languages: LanguagesSettingsConfig?
    /// Shows "Change password" (PUT /v2/users/me/password).
    public var changePassword: Bool?

    public init(languages: LanguagesSettingsConfig? = nil, changePassword: Bool? = nil) {
        self.languages = languages
        self.changePassword = changePassword
    }
}

/// The "Language" card: the interface language (`appLanguage`) and the language
/// messages are translated into (`chatLanguage`). Options default to en-CA,
/// es-US, fr-CA; pass BCP-47 tags to offer others.
public struct LanguagesSettingsConfig: Codable, Equatable {
    public var enabled: Bool
    public var appLanguages: [String]?
    public var chatLanguages: [String]?

    public init(enabled: Bool, appLanguages: [String]? = nil, chatLanguages: [String]? = nil) {
        self.enabled = enabled
        self.appLanguages = appLanguages
        self.chatLanguages = chatLanguages
    }
}
