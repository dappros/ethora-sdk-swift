//
//  MessageTranslationViews.swift
//  XMPPChatUI
//
//  Message translation for the live bubble, ported from web MessageBubble
//  (useMessageTranslation for auto mode, MessageTranslate for manual mode) and
//  the globe language sheet (LanguageSelectorModal).
//

import SwiftUI
import XMPPChatCore

// MARK: - Message text with translation

/// The text of one message, translated when the config and the reader call for it.
/// Auto mode shows the attached translation with the original quoted above it.
/// Manual mode shows the original with a "Translate" link.
struct TranslatableMessageText: View {
    let message: Message
    let isUser: Bool
    let foregroundColor: Color

    @ObservedObject private var preferences = LanguagePreferences.shared
    @State private var phase: TranslationPhase = .idle
    @State private var translatedText: String?
    @State private var showOriginal = false

    private var translates: TranslationsConfig? { ConfigStore.shared.config.translates }

    var body: some View {
        let enabled = translates?.enabled == true
        let readerLocale = preferences.readerLocale
        let resolved = MessageTranslationResolver.resolve(
            body: message.body,
            langSource: message.langSource,
            translations: message.translations,
            readerLocale: readerLocale
        )

        if !enabled {
            originalText
        } else if MessageTranslationResolver.resolveMode(translates, readerMode: preferences.readerMode) == .manual {
            manualBody(resolved: resolved)
        } else {
            autoBody(resolved: resolved)
        }
    }

    private var originalText: some View {
        UniversalMarkdownTextView(text: message.body, foregroundColor: foregroundColor)
    }

    // MARK: Auto

    @ViewBuilder
    private func autoBody(resolved: ResolvedMessageTranslation) -> some View {
        if resolved.hasTranslation, !isUser {
            VStack(alignment: .leading, spacing: 6) {
                Text(resolved.originalText)
                    .font(.caption)
                    .foregroundColor(foregroundColor.opacity(0.6))
                    .padding(.leading, 8)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(accentColor)
                            .frame(width: 2)
                    }
                UniversalMarkdownTextView(text: resolved.displayText, foregroundColor: foregroundColor)
            }
        } else {
            originalText
        }
    }

    // MARK: Manual

    @ViewBuilder
    private func manualBody(resolved: ResolvedMessageTranslation) -> some View {
        if showsTranslateLink(resolved: resolved) {
            VStack(alignment: .leading, spacing: 4) {
                switch phase {
                case .idle:
                    originalText
                    linkButton(UIStrings.t("action.translate")) { Task { await runTranslate(resolved: resolved) } }
                case .loading:
                    originalText
                    Text(UIStrings.t("translation.translating"))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(accentColor)
                case .error:
                    originalText
                    linkButton(UIStrings.t("translation.failed")) { Task { await runTranslate(resolved: resolved) } }
                case .done:
                    UniversalMarkdownTextView(
                        text: showOriginal ? message.body : (translatedText ?? message.body),
                        foregroundColor: foregroundColor
                    )
                    linkButton(showOriginal ? UIStrings.t("action.translate") : UIStrings.t("action.showOriginal")) {
                        showOriginal.toggle()
                    }
                }
            }
        } else {
            originalText
        }
    }

    /// Shows the link only when a click can reveal something: a translation is
    /// attached, the host has a translator, or a translate endpoint is set.
    private func showsTranslateLink(resolved: ResolvedMessageTranslation) -> Bool {
        if let predicate = translates?.showTranslateForMessage {
            return predicate(message)
        }
        guard resolved.needsTranslation else { return false }
        return resolved.hasTranslation || translates?.onTranslate != nil || translates?.endpoint != nil
    }

    private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(accentColor)
        }
        .buttonStyle(.plain)
    }

    /// The manual "Translate" action. Host translator first, then the translation
    /// already attached, then the opt-in endpoint.
    @MainActor
    private func runTranslate(resolved: ResolvedMessageTranslation) async {
        let text = message.body
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        phase = .loading
        let target = preferences.readerLocale
        var result: String?

        if let handler = translates?.onTranslate {
            result = try? await handler(text, message.langSource, target, message)
        } else {
            if resolved.hasTranslation {
                result = resolved.displayText
            } else if let endpoint = translates?.endpoint {
                let fetched = await TranslateServiceClient.shared.fetchTranslation(
                    text: text,
                    source: message.langSource,
                    readerLocale: target,
                    endpoint: endpoint
                )
                result = fetched?.translatedText
            }
        }

        if let result = result, !result.trimmingCharacters(in: .whitespaces).isEmpty {
            translatedText = result
            showOriginal = false
            phase = .done
        } else {
            phase = .error
        }
    }

    private var accentColor: Color {
        if let primary = ConfigStore.shared.config.colors?.primary, !primary.isEmpty {
            return Color(hex: primary)
        }
        return Color(hex: "#0052CD")
    }
}

private enum TranslationPhase {
    case idle, loading, done, error
}

// MARK: - Language sheet (globe)

/// The globe sheet from the chat header: the translate-my-messages switch,
/// the auto/manual choice (unless the host pins it), and the language list
/// (unless the host hides it).
struct TranslationLanguageSheet: View {
    @ObservedObject private var preferences = LanguagePreferences.shared
    @Environment(\.dismiss) private var dismiss

    private var translates: TranslationsConfig? { ConfigStore.shared.config.translates }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle(UIStrings.t("translation.enableToggleLabel"), isOn: Binding(
                        get: { preferences.translateSendEnabled != false },
                        set: { preferences.setTranslateSendEnabled($0) }
                    ))
                    Text(UIStrings.t("translation.enableToggleDisclaimer"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if MessageTranslationResolver.canReaderChooseMode(translates) {
                    Section(UIStrings.t("translation.modeLabel")) {
                        Picker(UIStrings.t("translation.modeLabel"), selection: Binding(
                            get: { MessageTranslationResolver.resolveMode(translates, readerMode: preferences.readerMode) },
                            set: { preferences.setReaderMode($0) }
                        )) {
                            Text(UIStrings.t("translation.modeAuto")).tag(TranslateMode.auto)
                            Text(UIStrings.t("translation.modeManual")).tag(TranslateMode.manual)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                if translates?.showLanguageList != false {
                    Section(UIStrings.t("language.select")) {
                        ForEach(LanguageOptions.choices(ConfigStore.shared.config.settings?.languages?.chatLanguages)) { choice in
                            Button {
                                Task { _ = await LanguagePreferences.shared.chooseChatLanguage(choice.id) }
                            } label: {
                                HStack {
                                    Text(choice.name)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if sameLanguage(choice.id, preferences.chatLanguage) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(UIStrings.t("language.select"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(UIStrings.t("action.close")) { dismiss() }
                }
            }
        }
    }

    private func sameLanguage(_ id: String, _ current: String?) -> Bool {
        guard let current = current else { return false }
        return id.caseInsensitiveCompare(current) == .orderedSame
    }
}
