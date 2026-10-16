import XCTest
@testable import XMPPChatCore

/// L1 tests for the theme config: scheme resolution, the colour palette
/// (ported from web buildThemeTokens) and typography decoding.
final class ThemeConfigTests: XCTestCase {

    // MARK: - Scheme resolution

    func testUnsetSchemeFollowsSystem() {
        XCTAssertEqual(ResolvedChatScheme.resolve(nil, systemIsDark: true), .dark)
        XCTAssertEqual(ResolvedChatScheme.resolve(nil, systemIsDark: false), .light)
    }

    func testSystemSchemeFollowsSystem() {
        XCTAssertEqual(ResolvedChatScheme.resolve(.system, systemIsDark: true), .dark)
        XCTAssertEqual(ResolvedChatScheme.resolve(.system, systemIsDark: false), .light)
    }

    func testForcedSchemeIgnoresSystem() {
        XCTAssertEqual(ResolvedChatScheme.resolve(.light, systemIsDark: true), .light)
        XCTAssertEqual(ResolvedChatScheme.resolve(.dark, systemIsDark: false), .dark)
    }

    // MARK: - Palette: light

    func testLightPaletteMatchesWebDefaults() {
        let palette = ChatPalette.resolve(colors: nil, scheme: .light)
        XCTAssertFalse(palette.isDark)
        XCTAssertEqual(palette.primary, "#0052CD")
        XCTAssertEqual(palette.primarySoft, "#E7EDF9")
        XCTAssertEqual(palette.text, "#141414")
        XCTAssertEqual(palette.background, "#FFFFFF")
        XCTAssertEqual(palette.backgroundSubtle, "#F5F7FA")
        XCTAssertEqual(palette.backgroundHover, "#F0F2F5")
        XCTAssertEqual(palette.chatBackground, "#F3F6FC")
        XCTAssertEqual(palette.border, "#E6E8EC")
        XCTAssertEqual(palette.divider, "#E6E8EC")
        XCTAssertEqual(palette.danger, "#D02B1F")
        XCTAssertEqual(palette.success, "#0C7C48")
        XCTAssertEqual(palette.online, palette.success)
    }

    func testInvalidPrimaryFallsBackToDefaultBlue() {
        let colors = ChatColors(primary: "not-a-colour", secondary: "#123456")
        let palette = ChatPalette.resolve(colors: colors, scheme: .light)
        XCTAssertEqual(palette.primary, "#0052CD")
        XCTAssertEqual(palette.primarySoft, "#E7EDF9")
    }

    func testCustomPrimaryDerivesSoftTint() {
        let colors = ChatColors(primary: "#FF0000", secondary: "#FFFFFF")
        let palette = ChatPalette.resolve(colors: colors, scheme: .light)
        XCTAssertEqual(palette.primary, "#FF0000")
        // tint(#FF0000, 0.88): red stays 255, green and blue become 255 * 0.88 = 224.4 -> 224 (0xE0)
        XCTAssertEqual(palette.primarySoft, "#ffe0e0")
        XCTAssertEqual(palette.primaryHover, "#eb0000")
    }

    func testEmptySecondaryFallsBackToPrimary() {
        let colors = ChatColors(primary: "#00AA00", secondary: "")
        let palette = ChatPalette.resolve(colors: colors, scheme: .light)
        XCTAssertEqual(palette.secondary, palette.primary)
    }

    func testSecondaryIsUsedInLight() {
        let colors = ChatColors(primary: "#00AA00", secondary: "#ABCDEF")
        let palette = ChatPalette.resolve(colors: colors, scheme: .light)
        XCTAssertEqual(palette.secondary, "#ABCDEF")
    }

    // MARK: - Palette: dark

    func testDarkPaletteMatchesWebNeutrals() {
        let palette = ChatPalette.resolve(colors: nil, scheme: .dark)
        XCTAssertTrue(palette.isDark)
        XCTAssertEqual(palette.text, "#ECEEF1")
        XCTAssertEqual(palette.textSecondary, "#B4B9C1")
        XCTAssertEqual(palette.background, "#1A1C21")
        XCTAssertEqual(palette.backgroundSubtle, "#202329")
        XCTAssertEqual(palette.backgroundHover, "#2A2D34")
        XCTAssertEqual(palette.border, "#34373F")
        XCTAssertEqual(palette.chatBackground, "#141619")
        XCTAssertEqual(palette.divider, "#0F1114")
        XCTAssertEqual(palette.danger, "#F2766B")
        XCTAssertEqual(palette.success, "#17864A")
        XCTAssertEqual(palette.online, "#3DD68C")
    }

    func testDarkPrimaryIsLiftedAndTextPrimaryIsLighter() {
        let palette = ChatPalette.resolve(colors: nil, scheme: .dark)
        // Lifted toward white so it stays visible on the dark surface.
        XCTAssertNotEqual(palette.primary, "#0052CD")
        XCTAssertGreaterThan(channel(palette.primary, shift: 16), channel("#0052CD", shift: 16))
        XCTAssertGreaterThan(channel(palette.primaryText, shift: 0), channel(palette.primary, shift: 0))
        XCTAssertGreaterThan(channel(palette.primaryText, shift: 8), channel(palette.primary, shift: 8))
    }

    func testDarkKeepsConfiguredSecondaryAndDarkSurfaces() {
        // The configured secondary is reported as-is, as on the web. Surfaces stay dark.
        let colors = ChatColors(primary: "#0052CD", secondary: "#F3F6FC")
        let palette = ChatPalette.resolve(colors: colors, scheme: .dark)
        XCTAssertEqual(palette.secondary, "#F3F6FC")
        XCTAssertEqual(palette.background, "#1A1C21")
    }

    func testDarkSoftTintComesFromPrimaryNotWhite() {
        let colors = ChatColors(primary: "#00AA00", secondary: "#FFFFFF")
        let palette = ChatPalette.resolve(colors: colors, scheme: .dark)
        // Mixed toward the dark surface, so every channel stays well below white.
        XCTAssertLessThan(channel(palette.primarySoft, shift: 0), 200)
        XCTAssertLessThan(channel(palette.primarySoft, shift: 8), 200)
        XCTAssertLessThan(channel(palette.primarySoft, shift: 16), 200)
    }

    // MARK: - Typography

    func testTypographyDecodesStringAndNumericFontSize() throws {
        let px = try JSONDecoder().decode(TypographyConfig.self, from: Data(#"{"fontSize":"18px"}"#.utf8))
        XCTAssertEqual(px.fontSize, 18)

        let number = try JSONDecoder().decode(TypographyConfig.self, from: Data(#"{"fontSize":16}"#.utf8))
        XCTAssertEqual(number.fontSize, 16)

        let unparsable = try JSONDecoder().decode(TypographyConfig.self, from: Data(#"{"fontSize":"1.1rem"}"#.utf8))
        XCTAssertNil(unparsable.fontSize)
    }

    func testFontFamilyStackPicksFirstInstalledFamily() {
        let config = TypographyConfig(fontFamily: "'e-Ukraine', \"Inter\", sans-serif")
        XCTAssertEqual(config.familyCandidates, ["e-Ukraine", "Inter", "sans-serif"])
        XCTAssertEqual(config.resolvedFamily(isInstalled: { $0 == "Inter" }), "Inter")
        XCTAssertNil(config.resolvedFamily(isInstalled: { _ in false }))
    }

    func testEmptyTypographyHasNoFamily() {
        XCTAssertEqual(TypographyConfig().familyCandidates, [])
        XCTAssertNil(TypographyConfig().resolvedFamily(isInstalled: { _ in true }))
    }

    // MARK: - ChatConfig persistence

    func testLegacyConfigWithoutThemeKeysDecodesWithNilThemeFields() throws {
        let json = Data(##"{"appId":"app","colors":{"primary":"#112233","secondary":"#445566"}}"##.utf8)
        let config = try JSONDecoder().decode(ChatConfig.self, from: json)
        XCTAssertNil(config.colorScheme)
        XCTAssertNil(config.typography)
        XCTAssertNil(config.supportsTablet)
        XCTAssertEqual(config.colors?.primary, "#112233")
        XCTAssertNil(config.colors?.ownMessageBackground)
    }

    func testThemeFieldsRoundTripThroughCodable() throws {
        var config = ChatConfig()
        config.colorScheme = .dark
        config.typography = TypographyConfig(fontFamily: "Inter", fontSize: 17)
        config.supportsTablet = false
        config.colors = ChatColors(primary: "#0052CD", secondary: "#F3F6FC", ownMessageBackground: "#112233")

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ChatConfig.self, from: data)

        XCTAssertEqual(decoded.colorScheme, .dark)
        XCTAssertEqual(decoded.typography, TypographyConfig(fontFamily: "Inter", fontSize: 17))
        XCTAssertEqual(decoded.supportsTablet, false)
        XCTAssertEqual(decoded.colors?.ownMessageBackground, "#112233")
    }

    // MARK: - Helpers

    /// Reads one RGB channel of a "#rrggbb" string: shift 16 = red, 8 = green, 0 = blue.
    private func channel(_ hex: String, shift: Int) -> Int {
        let digits = hex.dropFirst()
        let value = Int(digits, radix: 16) ?? 0
        return (value >> shift) & 0xFF
    }
}
