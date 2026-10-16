//
//  ChatTheme.swift
//  XMPPChatUI
//
//  Puts the resolved colour palette, colour scheme and base font into the
//  chat's view tree. Counterpart of ThemeTokens / useThemeTokenStyle on web.
//

import SwiftUI
import XMPPChatCore

private struct ChatPaletteKey: EnvironmentKey {
    static let defaultValue = ChatPalette.resolve(colors: nil, scheme: .light)
}

public extension EnvironmentValues {
    /// The chat's resolved colour palette. `ChatWrapperView` sets it from `ChatConfig`.
    var chatPalette: ChatPalette {
        get { self[ChatPaletteKey.self] }
        set { self[ChatPaletteKey.self] = newValue }
    }
}

extension View {
    /// Applies the config's colour scheme, palette and font to this view tree.
    func chatTheme(_ config: ChatConfig) -> some View {
        modifier(ChatThemeModifier(config: config))
    }
}

/// Resolves `config.colorScheme` against the OS appearance and injects the
/// matching palette. A forced scheme also sets `preferredColorScheme`, so
/// system colours in the chat follow it. `.system` and unset leave the host's
/// own scheme alone.
struct ChatThemeModifier: ViewModifier {
    let config: ChatConfig

    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.font) private var inheritedFont

    func body(content: Content) -> some View {
        let scheme = ResolvedChatScheme.resolve(
            config.colorScheme,
            systemIsDark: systemColorScheme == .dark
        )
        let palette = ChatPalette.resolve(colors: config.colors, scheme: scheme)
        content
            .environment(\.chatPalette, palette)
            .environment(\.font, chatBaseFont ?? inheritedFont)
            .chatForcedColorScheme(config.colorScheme)
    }

    /// The configured base font. Nil when `typography` sets neither a family
    /// nor a size, so text keeps the host's font.
    private var chatBaseFont: Font? {
        guard let typography = config.typography else { return nil }
        let family = typography.resolvedFamily(isInstalled: ChatFontAvailability.isInstalled)
        guard family != nil || typography.fontSize != nil else { return nil }
        let pointSize = CGFloat(typography.fontSize ?? 17)
        if let family {
            // Relative to body so the family still scales with Dynamic Type.
            return .custom(family, size: pointSize, relativeTo: .body)
        }
        return .system(size: pointSize)
    }
}

private extension View {
    @ViewBuilder
    func chatForcedColorScheme(_ scheme: ChatColorScheme?) -> some View {
        switch scheme {
        case .light?:
            self.preferredColorScheme(.light)
        case .dark?:
            self.preferredColorScheme(.dark)
        case .system?, nil:
            self
        }
    }
}

enum ChatFontAvailability {
    /// True when the host has the family installed (bundled via UIAppFonts or registered).
    static func isInstalled(_ name: String) -> Bool {
        #if os(iOS)
        return UIFont.familyNames.contains(name) || UIFont(name: name, size: 12) != nil
        #else
        return NSFontManager.shared.availableFontFamilies.contains(name)
        #endif
    }
}
