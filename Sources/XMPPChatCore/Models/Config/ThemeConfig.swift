//
//  ThemeConfig.swift
//  XMPPChatCore
//
//  Colour scheme and typography config keys, named after the web IConfig
//  (`colorScheme`, `typography`) so one config shape works on both SDKs.
//

import Foundation

/// Which colour scheme the chat renders in. `.system` follows the OS setting.
/// Mirrors `ChatColorScheme` in the web component.
public enum ChatColorScheme: String, Codable, Equatable, CaseIterable {
    case light
    case dark
    case system
}

/// The scheme actually rendered once `.system` (or an unset value) is resolved
/// against the OS appearance.
public enum ResolvedChatScheme: String, Equatable {
    case light
    case dark

    /// Resolve a configured scheme. `nil` and `.system` both follow the OS.
    /// Native apps already follow the OS by default, so an unset value keeps
    /// existing apps looking the same. (The web default is `light` because its
    /// colours were hard-coded for a white page.)
    public static func resolve(_ scheme: ChatColorScheme?, systemIsDark: Bool) -> ResolvedChatScheme {
        switch scheme {
        case .light:
            return .light
        case .dark:
            return .dark
        case .system, .none:
            return systemIsDark ? .dark : .light
        }
    }
}

/// Font configuration, mirroring web `TypographyConfig`.
///
/// Native support is partial. `fontFamily` and `fontSize` are applied by the
/// UI layer. The Google Fonts keys are decoded so one config works on both
/// SDKs, but iOS cannot load them at runtime. Bundle the font with the host
/// app (UIAppFonts) and name it in `fontFamily`.
public struct TypographyConfig: Codable, Equatable {
    /// Family for the chat text. May be a comma-separated fallback stack such
    /// as "e-Ukraine, Inter, sans-serif" (see `resolvedFamily(isInstalled:)`).
    public var fontFamily: String?
    /// Base text size in points. A number, or a numeric string with an
    /// optional "px" suffix (the web accepts both).
    public var fontSize: Double?
    /// Web-only: a Google Fonts stylesheet URL. Decoded, not loaded natively.
    public var googleFontsUrl: String?
    /// Web-only: a Google family name. Decoded, not loaded natively.
    public var googleFontsFamily: String?

    public init(
        fontFamily: String? = nil,
        fontSize: Double? = nil,
        googleFontsUrl: String? = nil,
        googleFontsFamily: String? = nil
    ) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.googleFontsUrl = googleFontsUrl
        self.googleFontsFamily = googleFontsFamily
    }

    private enum CodingKeys: String, CodingKey {
        case fontFamily, fontSize, googleFontsUrl, googleFontsFamily
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily)
        self.fontSize = Self.decodeFontSize(container)
        self.googleFontsUrl = try container.decodeIfPresent(String.self, forKey: .googleFontsUrl)
        self.googleFontsFamily = try container.decodeIfPresent(String.self, forKey: .googleFontsFamily)
    }

    private static func decodeFontSize(_ container: KeyedDecodingContainer<CodingKeys>) -> Double? {
        if let number = try? container.decodeIfPresent(Double.self, forKey: .fontSize) {
            return number
        }
        if let text = try? container.decodeIfPresent(String.self, forKey: .fontSize) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "px", with: "")
            return Double(trimmed)
        }
        return nil
    }

    /// Family names from `fontFamily` in stack order, with quotes and
    /// whitespace removed. Empty entries are dropped.
    public var familyCandidates: [String] {
        guard let fontFamily else { return [] }
        return fontFamily
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "'\""))) }
            .filter { !$0.isEmpty }
    }

    /// The first family in the stack the host has installed, or nil when none is.
    /// The UI passes an availability check (for example `UIFont(name:size:) != nil`).
    public func resolvedFamily(isInstalled: (String) -> Bool) -> String? {
        familyCandidates.first(where: isInstalled)
    }
}
