//
//  MessageTranslation.swift
//  XMPPChatCore
//
//  Message translation model
//

import Foundation

public struct MessageTranslation: Codable, Equatable {
    public let translatedText: String
    public let sourceLanguage: String?
    public let targetLanguage: String?
    
    public init(
        translatedText: String,
        sourceLanguage: String? = nil,
        targetLanguage: String? = nil
    ) {
        self.translatedText = translatedText
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
    }
}
