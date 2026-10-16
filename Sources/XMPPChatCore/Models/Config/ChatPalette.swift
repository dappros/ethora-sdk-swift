//
//  ChatPalette.swift
//  XMPPChatCore
//
//  Colour tokens for the chat, derived from the host's `ChatColors`. Translated
//  from buildThemeTokens in web src/styles/tokens.ts, including the dark
//  neutrals and the lifted brand colour used on dark surfaces. Pure value
//  logic, so it stays UI-agnostic and testable.
//

import Foundation

/// Every colour token the chat's dark and light schemes use. Values are hex
/// strings ("#RRGGBB"), so the UI layer converts them with `Color(hex:)`.
public struct ChatPalette: Equatable {
    public let scheme: ResolvedChatScheme

    /// Brand colour for buttons, own bubbles and accents. Lifted in dark so it
    /// stays visible on a dark surface while white text on it still reads.
    public let primary: String
    public let primaryHover: String
    /// Primary used as text or icon colour (links, headers). Lifted further in dark.
    public let primaryText: String
    /// Soft brand tint for selected rows and quote panels.
    public let primarySoft: String
    public let secondary: String

    public let text: String
    public let textSecondary: String
    public let textMuted: String
    public let textOnPrimary: String

    public let background: String
    public let backgroundSubtle: String
    public let backgroundHover: String
    public let chatBackground: String
    public let border: String
    /// Hairline between two chat surfaces (composer and message area).
    public let divider: String

    public let danger: String
    public let success: String
    /// Presence-dot and "online" text colour. Brighter than `success` in dark.
    public let online: String

    public var isDark: Bool { scheme == .dark }

    /// Build the palette for a host's colours and a resolved scheme.
    ///
    /// - An invalid or empty `primary` falls back to the default brand blue.
    /// - Empty optional colours fall back to the derived defaults, as on the web.
    public static func resolve(colors: ChatColors?, scheme: ResolvedChatScheme) -> ChatPalette {
        let dark = scheme == .dark
        let neutrals = dark ? Neutrals.dark : Neutrals.light

        let configuredPrimary = validHex(colors?.primary) ?? defaultPrimary
        let customPrimary = validHex(colors?.primary) != nil

        let primary = dark ? ChatColorMath.tint(configuredPrimary, 0.2) : configuredPrimary
        let primaryText = dark ? ChatColorMath.tint(configuredPrimary, 0.45) : primary
        let primarySoft: String
        if dark {
            primarySoft = ChatColorMath.mix(configuredPrimary, neutrals.background, 0.72)
        } else if customPrimary {
            primarySoft = ChatColorMath.tint(primary, 0.88)
        } else {
            primarySoft = defaultPrimarySoft
        }

        // Light fallback goes to `secondary`, as the web does. Dark ignores it,
        // since a light-page secondary colour would paint a near-white block on a dark surface.
        let secondary = nonEmpty(colors?.secondary) ?? primary

        return ChatPalette(
            scheme: scheme,
            primary: primary,
            primaryHover: ChatColorMath.shade(primary, 0.08),
            primaryText: primaryText,
            primarySoft: primarySoft,
            secondary: secondary,
            text: neutrals.text,
            textSecondary: neutrals.textSecondary,
            textMuted: neutrals.textMuted,
            textOnPrimary: neutrals.textOnPrimary,
            background: neutrals.background,
            backgroundSubtle: neutrals.backgroundSubtle,
            backgroundHover: neutrals.backgroundHover,
            chatBackground: neutrals.chatBackground,
            border: neutrals.border,
            divider: neutrals.divider,
            danger: neutrals.danger,
            success: neutrals.success,
            online: dark ? darkOnline : neutrals.success
        )
    }

    // MARK: - Defaults (mirror web DEFAULTS and DARK_DEFAULTS)

    private static let defaultPrimary = "#0052CD"
    private static let defaultPrimarySoft = "#E7EDF9"
    private static let darkOnline = "#3DD68C"

    private static func validHex(_ value: String?) -> String? {
        guard let value, ChatColorMath.isValidHex(value) else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
}

/// Neutral surface and text values for one scheme. Dark values keep text
/// above WCAG AA (4.5:1) on each surface they sit on.
private struct Neutrals {
    let text: String
    let textSecondary: String
    let textMuted: String
    let textOnPrimary: String
    let background: String
    let backgroundSubtle: String
    let backgroundHover: String
    let chatBackground: String
    let border: String
    let divider: String
    let danger: String
    let success: String

    static let light = Neutrals(
        text: "#141414",
        textSecondary: "#5A5F66",
        textMuted: "#6C6C6C",
        textOnPrimary: "#FFFFFF",
        background: "#FFFFFF",
        backgroundSubtle: "#F5F7FA",
        backgroundHover: "#F0F2F5",
        chatBackground: "#F3F6FC",
        border: "#E6E8EC",
        divider: "#E6E8EC",
        danger: "#D02B1F",
        success: "#0C7C48"
    )

    static let dark = Neutrals(
        text: "#ECEEF1",
        textSecondary: "#B4B9C1",
        textMuted: "#9AA1AB",
        textOnPrimary: "#FFFFFF",
        background: "#1A1C21",
        backgroundSubtle: "#202329",
        backgroundHover: "#2A2D34",
        chatBackground: "#141619",
        border: "#34373F",
        divider: "#0F1114",
        danger: "#F2766B",
        success: "#17864A"
    )
}

/// Hex colour arithmetic used to derive palette tokens. Matches the web
/// helpers (`tintColor`, `shadeColor`, `mixColor`).
enum ChatColorMath {
    static func isValidHex(_ value: String) -> Bool {
        var hex = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 3 || hex.count == 6 else { return false }
        return hex.allSatisfy { $0.isHexDigit }
    }

    /// Mix toward white by `amount` (0 to 1).
    static func tint(_ hex: String, _ amount: Double) -> String {
        guard let c = rgb(hex) else { return hex }
        return format(
            c.r + (255 - c.r) * amount,
            c.g + (255 - c.g) * amount,
            c.b + (255 - c.b) * amount
        )
    }

    /// Mix toward black by `amount` (0 to 1).
    static func shade(_ hex: String, _ amount: Double) -> String {
        guard let c = rgb(hex) else { return hex }
        return format(c.r * (1 - amount), c.g * (1 - amount), c.b * (1 - amount))
    }

    /// Mix `a` toward `b` by `amount` (0 to 1).
    static func mix(_ a: String, _ b: String, _ amount: Double) -> String {
        guard let x = rgb(a), let y = rgb(b) else { return a }
        return format(
            x.r + (y.r - x.r) * amount,
            x.g + (y.g - x.g) * amount,
            x.b + (y.b - x.b) * amount
        )
    }

    private static func rgb(_ value: String) -> (r: Double, g: Double, b: Double)? {
        guard isValidHex(value) else { return nil }
        var hex = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        guard let number = Int(hex, radix: 16) else { return nil }
        return (
            Double((number >> 16) & 255),
            Double((number >> 8) & 255),
            Double(number & 255)
        )
    }

    private static func format(_ r: Double, _ g: Double, _ b: Double) -> String {
        func channel(_ v: Double) -> String {
            let clamped = max(0, min(255, v.rounded()))
            return String(format: "%02x", Int(clamped))
        }
        return "#" + channel(r) + channel(g) + channel(b)
    }
}
