//
//  MessageTranslationsView.swift
//  XMPPChatUI
//
//  Message translations component
//

import SwiftUI
import XMPPChatCore

public struct MessageTranslationsView: View {
    let message: Message
    let isUser: Bool
    let langSource: String
    let config: ChatConfig?
    
    public init(
        message: Message,
        isUser: Bool,
        langSource: String = "en",
        config: ChatConfig? = nil
    ) {
        self.message = message
        self.isUser = isUser
        self.langSource = langSource
        self.config = config
    }
    
    public var body: some View {
        if let translations = message.translations,
           let translation = translations[langSource],
           !translation.translatedText.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                // Divider
                Divider()
                    .background(Color(hex: isUser ? (config?.colors?.secondary ?? "#E1E4FE") : (config?.colors?.primary ?? "#5E3FDE")))
                
                // Translated text
                Text(translation.translatedText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .italic()
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Translation Language Selector
public struct TranslationLanguageSelector: View {
    @Binding var selectedLanguage: String
    let availableLanguages: [String]
    let onLanguageChanged: (String) -> Void
    
    public init(
        selectedLanguage: Binding<String>,
        availableLanguages: [String] = ["en", "es", "pt", "ht", "zh"],
        onLanguageChanged: @escaping (String) -> Void
    ) {
        self._selectedLanguage = selectedLanguage
        self.availableLanguages = availableLanguages
        self.onLanguageChanged = onLanguageChanged
    }
    
    public var body: some View {
        Menu {
            ForEach(availableLanguages, id: \.self) { lang in
                Button(action: {
                    selectedLanguage = lang
                    onLanguageChanged(lang)
                }) {
                    HStack {
                        Text(languageName(for: lang))
                        if selectedLanguage == lang {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack {
                Image(systemName: "globe")
                Text(languageName(for: selectedLanguage))
            }
            .font(.caption)
            .foregroundColor(.blue)
        }
    }
    
    private func languageName(for code: String) -> String {
        switch code {
        case "en": return "English"
        case "es": return "Spanish"
        case "pt": return "Portuguese"
        case "ht": return "Haitian Creole"
        case "zh": return "Chinese"
        default: return code.uppercased()
        }
    }
}
