//
//  LocalizationAndTranslationTests.swift
//  XMPPChatCoreTests
//
//  Pure-logic tests for UI captions, language tags, message translation rules,
//  the `<translate source>` send stanza and the account API routes.
//

import XCTest
@testable import XMPPChatCore

final class LocalizationAndTranslationTests: XCTestCase {

    // MARK: - Captions

    func testBaseLanguageReducesRegionalLocale() {
        XCTAssertEqual(UIStrings.baseLanguage("fr-CA"), "fr")
        XCTAssertEqual(UIStrings.baseLanguage("es_US"), "es")
        XCTAssertEqual(UIStrings.baseLanguage(nil), "en")
        XCTAssertEqual(UIStrings.baseLanguage(""), "en")
    }

    func testTableCompletenessEveryLanguageHasEveryEnglishKey() {
        let englishKeys = Set(UIStringTables.en.keys)
        for (language, table) in UIStringTables.byLanguage where language != "en" {
            XCTAssertTrue(englishKeys.isSubset(of: Set(table.keys)), "\(language) is missing keys")
        }
    }

    func testTablesHaveNoEmptyValues() {
        for (language, table) in UIStringTables.byLanguage {
            let empty = table.filter { $0.value.trimmingCharacters(in: .whitespaces).isEmpty }.map(\.key)
            XCTAssertEqual(empty, [], "\(language) has empty values")
        }
    }

    func testPlaceholdersMatchEnglishInEveryLanguage() {
        func placeholders(_ text: String) -> [String] {
            let pattern = try! NSRegularExpression(pattern: "\\{(\\w+)\\}")
            let range = NSRange(text.startIndex..., in: text)
            return pattern.matches(in: text, range: range).compactMap { match in
                Range(match.range(at: 1), in: text).map { String(text[$0]) }
            }.sorted()
        }
        for (language, table) in UIStringTables.byLanguage where language != "en" {
            for (key, english) in UIStringTables.en {
                guard let translated = table[key] else { continue }
                XCTAssertEqual(placeholders(translated), placeholders(english), "\(language).\(key)")
            }
        }
    }

    func testTranslateUsesBaseLanguageTable() {
        XCTAssertEqual(
            UIStrings.translate("action.add", locale: "fr-CA"),
            UIStringTables.fr["action.add"]
        )
    }

    func testTranslateFallsBackToEnglishThenKey() {
        XCTAssertEqual(UIStrings.translate("action.add", locale: "xx"), UIStringTables.en["action.add"])
        XCTAssertEqual(UIStrings.translate("no.such.key", locale: "fr"), "no.such.key")
    }

    func testHostOverridesWin() {
        XCTAssertEqual(
            UIStrings.translate("action.add", locale: "fr", overrides: ["action.add": "Custom"]),
            "Custom"
        )
    }

    func testInterpolateReplacesKnownPlaceholdersOnly() {
        XCTAssertEqual(
            UIStrings.interpolate("Add users ({count} selected)", vars: ["count": "3"]),
            "Add users (3 selected)"
        )
        XCTAssertEqual(UIStrings.interpolate("{missing} stays", vars: ["count": "3"]), "{missing} stays")
    }

    // MARK: - Language tags

    func testLanguageTagCanonicalForm() {
        XCTAssertEqual(LanguageTag.canonical("en-ca"), "en-CA")
        XCTAssertEqual(LanguageTag.canonical("FR"), "fr")
        XCTAssertNil(LanguageTag.canonical("not a tag!"))
        XCTAssertNil(LanguageTag.canonical(nil))
    }

    func testLanguageLabelUsesOfferListThenAutonym() {
        XCTAssertEqual(LanguageTag.label(for: "fr-CA"), "Français")
        XCTAssertEqual(LanguageTag.label(for: "pt"), "Português")
    }

    // MARK: - Message translation rules

    private let translations: [String: MessageTranslation] = [
        "en-CA": MessageTranslation(translatedText: "hello there"),
    ]

    func testTranslationAttachedForDifferentSourceLanguage() {
        let resolved = MessageTranslationResolver.resolve(
            body: "bonjour",
            langSource: "fr",
            translations: translations,
            readerLocale: "en-CA"
        )
        XCTAssertTrue(resolved.needsTranslation)
        XCTAssertTrue(resolved.hasTranslation)
        XCTAssertEqual(resolved.displayText, "hello there")
        XCTAssertEqual(resolved.originalText, "bonjour")
    }

    func testSameLanguageNeedsNoTranslation() {
        let resolved = MessageTranslationResolver.resolve(
            body: "hello",
            langSource: "en-US",
            translations: translations,
            readerLocale: "en-CA"
        )
        XCTAssertFalse(resolved.needsTranslation)
        XCTAssertFalse(resolved.hasTranslation)
    }

    func testNumbersOnlyNeedNoTranslation() {
        let resolved = MessageTranslationResolver.resolve(
            body: "42",
            langSource: "fr",
            translations: translations,
            readerLocale: "en"
        )
        XCTAssertFalse(resolved.needsTranslation)
    }

    func testIdenticalTranslationIsNotShown() {
        let resolved = MessageTranslationResolver.resolve(
            body: "bonjour",
            langSource: "fr",
            translations: ["en-CA": MessageTranslation(translatedText: "bonjour")],
            readerLocale: "en-CA"
        )
        XCTAssertTrue(resolved.needsTranslation)
        XCTAssertFalse(resolved.hasTranslation)
        XCTAssertEqual(resolved.displayText, "bonjour")
    }

    func testForcedModeWinsOverReaderChoice() {
        let config = TranslationsConfig(enabled: true, mode: .auto, forceType: true)
        XCTAssertEqual(MessageTranslationResolver.resolveMode(config, readerMode: .manual), .auto)
        XCTAssertFalse(MessageTranslationResolver.canReaderChooseMode(config))
    }

    func testReaderChoiceWinsOverHostDefaultWhenNotForced() {
        let config = TranslationsConfig(enabled: true, mode: .auto)
        XCTAssertEqual(MessageTranslationResolver.resolveMode(config, readerMode: .manual), .manual)
        XCTAssertEqual(MessageTranslationResolver.resolveMode(config, readerMode: nil), .auto)
    }

    func testOutgoingSourceTagRules() {
        XCTAssertTrue(MessageTranslationResolver.shouldTagOutgoingSource(translatesEnabled: true, translateSendEnabled: nil))
        XCTAssertFalse(MessageTranslationResolver.shouldTagOutgoingSource(translatesEnabled: true, translateSendEnabled: false))
        XCTAssertFalse(MessageTranslationResolver.shouldTagOutgoingSource(translatesEnabled: false, translateSendEnabled: nil))
    }

    // MARK: - Stanzas

    func testTranslateTagIsAddedOnlyWhenSourceGiven() {
        let data = XMPPStanza(name: "data", attributes: ["roomJid": "room@conf.test"])
        let tagged = XMPPOperations.buildTextMessageStanza(
            id: "send-text-message-1",
            roomJID: "room@conf.test",
            dataStanza: data,
            userMessage: "hi",
            translateSource: "fr"
        )
        XCTAssertEqual(tagged.getChild("translate")?.attributes["source"], "fr")

        let plain = XMPPOperations.buildTextMessageStanza(
            id: "send-text-message-2",
            roomJID: "room@conf.test",
            dataStanza: data,
            userMessage: "hi",
            translateSource: nil
        )
        XCTAssertNil(plain.getChild("translate"))
    }

    func testTranslateTagRoundTripsThroughParser() {
        let data = XMPPStanza(name: "data", attributes: ["roomJid": "room@conf.test"])
        let outgoing = XMPPOperations.buildTextMessageStanza(
            id: "send-text-message-3",
            roomJID: "room@conf.test",
            dataStanza: data,
            userMessage: "bonjour",
            translateSource: "fr"
        )
        // Re-address it as an inbound MUC stanza, then parse it as a reader would.
        let inbound = XMPPStanza(
            name: "message",
            attributes: ["id": "msg-1700000000000", "from": "room@conf.test/alice", "type": "groupchat"],
            children: outgoing.children
        )
        XCTAssertEqual(MessageParser.getDataFromStanza(inbound)?.langSource, "fr")
    }

    // MARK: - Account routes

    func testAccountEndpointKeepsOriginAndReplacesVersion() {
        let base = URL(string: "https://api.chat.ethora.com/v1")!
        XCTAssertEqual(
            AccountAPI.endpointURL(baseURL: base, version: "v1", path: "users")?.absoluteString,
            "https://api.chat.ethora.com/v1/users"
        )
        XCTAssertEqual(
            AccountAPI.endpointURL(baseURL: base, version: "v2", path: "users/me/password")?.absoluteString,
            "https://api.chat.ethora.com/v2/users/me/password"
        )
    }

    func testAccountErrorReasonIsReadFromJSONMessage() {
        let body = Data(#"{"message":"The current password is not right"}"#.utf8)
        XCTAssertEqual(AccountAPI.reason(from: body), "The current password is not right")
        XCTAssertEqual(AccountAPI.reason(from: Data("plain text".utf8)), "plain text")
    }

    // MARK: - Translations config persistence

    func testTranslationsConfigPersistsDataFieldsOnly() throws {
        let config = TranslationsConfig(
            enabled: true,
            mode: .manual,
            forceType: false,
            readerLocale: "fr-CA",
            endpoint: "https://translate.example.com/translate",
            onTranslate: { _, _, _, _ in nil }
        )
        let decoded = try JSONDecoder().decode(TranslationsConfig.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded, config)
        XCTAssertNil(decoded.onTranslate)
    }
}
