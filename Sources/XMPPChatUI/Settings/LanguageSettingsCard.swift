//
//  LanguageSettingsCard.swift
//  XMPPChatUI
//
//  The "Language" section of the settings screen: the interface language
//  (appLanguage) and the language messages are translated into (chatLanguage).
//  Shown when `settings.languages.enabled` is true.
//

import SwiftUI
import XMPPChatCore

/// One choice in a language list.
struct LanguageOption: Identifiable, Equatable {
    let id: String
    let name: String
}

enum LanguageOptions {
    /// The host's list when it sets one (canonicalised), else the built-in offer.
    static func choices(_ ids: [String]?) -> [LanguageOption] {
        let canonical = (ids ?? []).compactMap { LanguageTag.canonical($0) }
        if canonical.isEmpty {
            return LanguageTag.defaultOptions.map { LanguageOption(id: $0.id, name: $0.name) }
        }
        return canonical.map { LanguageOption(id: $0, name: LanguageTag.label(for: $0)) }
    }
}

struct LanguageSettingsCard: View {
    @ObservedObject private var preferences = LanguagePreferences.shared
    @ObservedObject private var configStore = ConfigStore.shared

    private var languages: LanguagesSettingsConfig? { configStore.config.settings?.languages }

    var body: some View {
        let appOptions = LanguageOptions.choices(languages?.appLanguages)
        let chatOptions = LanguageOptions.choices(languages?.chatLanguages)

        Section {
            languageGroup(
                title: UIStrings.t("settings.language.app"),
                hint: UIStrings.t("settings.language.appHint"),
                options: appOptions,
                current: preferences.uiLocale ?? configStore.config.i18n?.locale
            ) { id in
                Task { _ = await preferences.chooseAppLanguage(id) }
            }

            languageGroup(
                title: UIStrings.t("settings.language.chat"),
                hint: UIStrings.t("settings.language.chatHint"),
                options: chatOptions,
                current: preferences.chatLanguage ?? preferences.uiLocale
            ) { id in
                Task { _ = await preferences.chooseChatLanguage(id) }
            }
        } header: {
            Text(UIStrings.t("settings.language.app"))
        }
    }

    @ViewBuilder
    private func languageGroup(
        title: String,
        hint: String,
        options: [LanguageOption],
        current: String?,
        onPick: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(hint)
                .font(.caption)
                .foregroundColor(.secondary)
            ForEach(options) { option in
                Button {
                    onPick(option.id)
                } label: {
                    HStack {
                        Text(option.name)
                            .foregroundColor(.primary)
                        Spacer()
                        if isSame(option.id, current) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSame(option.id, current) ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private func isSame(_ id: String, _ current: String?) -> Bool {
        guard let current = current else { return false }
        return id.caseInsensitiveCompare(current) == .orderedSame
    }
}
