//
//  TranslationConfig.swift
//  XMPPChatCore
//

import Foundation

public enum Iso639_1Code: String, Codable {
    case en = "en"
    case es = "es"
    case pt = "pt"
    case ht = "ht"
    case zh = "zh"
}

public struct TranslationsConfig: Codable, Equatable {
    public let enabled: Bool
    public let translations: Iso639_1Code?
    
    public init(enabled: Bool, translations: Iso639_1Code? = nil) {
        self.enabled = enabled
        self.translations = translations
    }
}
