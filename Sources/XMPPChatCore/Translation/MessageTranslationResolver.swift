//
//  MessageTranslationResolver.swift
//  XMPPChatCore
//
//  Message translation rules, ported from web helpers/resolveMessageTranslation.ts,
//  utils/translateModePolicy.ts and networking/api-requests/translate.api.ts.
//  Pure functions, plus the opt-in translate-service call used by manual mode.
//

import Foundation

/// What the reader should see for one message.
public struct ResolvedMessageTranslation: Equatable {
    /// The message has text in another language than the reader's.
    public let needsTranslation: Bool
    /// A real translation (not identical to the original) is attached.
    public let hasTranslation: Bool
    public let originalText: String
    /// `translatedText` when `hasTranslation`, else the original.
    public let displayText: String
}

public enum MessageTranslationResolver {

    // MARK: - Resolution

    /// Decides whether there is a translation to show for this reader. This is the
    /// one lookup auto and manual mode both use, so they agree.
    public static func resolve(
        body: String,
        langSource: String?,
        translations: [String: MessageTranslation]?,
        readerLocale: String?
    ) -> ResolvedMessageTranslation {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetBase = UIStrings.baseLanguage(readerLocale)
        let sourceBase = langSource.flatMap { $0.isEmpty ? nil : UIStrings.baseLanguage($0) }

        // Nothing to translate when the source language is unknown, it already
        // matches the reader's (region ignored), or there are no letters at all.
        let needsTranslation = !trimmed.isEmpty
            && sourceBase != nil
            && sourceBase != targetBase
            && containsLetter(trimmed)

        var attached: String? = nil
        if needsTranslation {
            let exact = readerLocale.flatMap { translations?[$0]?.translatedText }
            attached = exact ?? translations?[targetBase]?.translatedText
        }

        // A "translation" identical to the original is no translation.
        let isReal = attached.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) != trimmed } ?? false
        return ResolvedMessageTranslation(
            needsTranslation: needsTranslation,
            hasTranslation: isReal,
            originalText: body,
            displayText: isReal ? (attached ?? body) : body
        )
    }

    /// The mode in effect. `forceType` wins, then the reader's own pick, then the host default, then auto.
    public static func resolveMode(
        _ translates: TranslationsConfig?,
        readerMode: TranslateMode?
    ) -> TranslateMode {
        let hostDefault = translates?.mode ?? .auto
        if translates?.forceType == true { return hostDefault }
        return readerMode ?? hostDefault
    }

    /// Whether the reader can switch auto/manual themselves.
    public static func canReaderChooseMode(_ translates: TranslationsConfig?) -> Bool {
        translates?.forceType != true
    }

    /// Whether outgoing text is tagged with `<translate source>`: the host enables
    /// translation, and the reader has not turned "Translate my messages" off.
    public static func shouldTagOutgoingSource(
        translatesEnabled: Bool,
        translateSendEnabled: Bool?
    ) -> Bool {
        translatesEnabled && translateSendEnabled != false
    }

    /// Letters in any script. "42", "+1 555-0100" or an emoji have nothing to translate.
    static func containsLetter(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }
}

// MARK: - Translate service (manual mode, opt-in)

/// A translation from the built-in service: the language it is for and its text.
public struct FetchedTranslation: Equatable {
    public let language: String
    public let translatedText: String
}

/// Calls the translate service at `config.translates.endpoint`. Tries GET
/// `?source=&text=` (the multi-locale shape), and falls back to POST `{text, source,
/// target, targetLocale}` when the GET route is missing (404/405). Never throws:
/// any failure is nil, which the UI shows as "Could not translate".
public actor TranslateServiceClient {
    public static let shared = TranslateServiceClient()

    /// Session used for requests. Injectable for tests.
    private let session: URLSession
    public static let requestTimeout: TimeInterval = 5

    private var getMissing: Set<String> = []
    private var postMissing: Set<String> = []
    private var endpointMissing: Set<String> = []

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Clears the 404 memory, for tests.
    public func resetAvailability() {
        getMissing.removeAll()
        postMissing.removeAll()
        endpointMissing.removeAll()
    }

    public func fetchTranslation(
        text: String,
        source: String?,
        readerLocale: String,
        endpoint: String?
    ) async -> FetchedTranslation? {
        guard let endpoint = endpoint, !endpoint.isEmpty,
              let source = source, !source.isEmpty,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: endpoint) else { return nil }
        if endpointMissing.contains(endpoint) { return nil }

        let baseSource = UIStrings.baseLanguage(source)

        if !getMissing.contains(endpoint) {
            switch await tryGet(url: url, text: text, source: baseSource, readerLocale: readerLocale) {
            case .found(let entry): return entry
            case .notFound: getMissing.insert(endpoint)
            }
        }

        if postMissing.contains(endpoint) {
            endpointMissing.insert(endpoint)
            return nil
        }

        switch await tryPost(url: url, text: text, source: baseSource, readerLocale: readerLocale) {
        case .found(let entry): return entry
        case .notFound:
            postMissing.insert(endpoint)
            endpointMissing.insert(endpoint)
            return nil
        }
    }

    private enum RouteResult {
        case found(FetchedTranslation?)
        case notFound
    }

    private func tryGet(url: URL, text: String, source: String, readerLocale: String) async -> RouteResult {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var items = components?.queryItems ?? []
        items.append(URLQueryItem(name: "source", value: source))
        items.append(URLQueryItem(name: "text", value: text))
        components?.queryItems = items
        guard let requestURL = components?.url else { return .found(nil) }
        var request = URLRequest(url: requestURL, timeoutInterval: Self.requestTimeout)
        request.httpMethod = "GET"
        do {
            let (data, response) = try await session.data(for: request)
            if let status = (response as? HTTPURLResponse)?.statusCode, [404, 405].contains(status) {
                return .notFound
            }
            guard let decoded = try? JSONDecoder().decode(MultiLocaleResponse.self, from: data) else {
                return .found(nil)
            }
            return .found(pickEntry(decoded.translates, readerLocale: readerLocale))
        } catch {
            return .found(nil)
        }
    }

    private func tryPost(url: URL, text: String, source: String, readerLocale: String) async -> RouteResult {
        var request = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "text": text,
            "source": source,
            "target": UIStrings.baseLanguage(readerLocale),
            "targetLocale": readerLocale,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await session.data(for: request)
            if let status = (response as? HTTPURLResponse)?.statusCode, [404, 405].contains(status) {
                return .notFound
            }
            guard let decoded = try? JSONDecoder().decode(SingleResponse.self, from: data),
                  let translated = decoded.translatedText, !translated.isEmpty else {
                return .found(nil)
            }
            return .found(FetchedTranslation(language: readerLocale, translatedText: translated))
        } catch {
            return .found(nil)
        }
    }

    /// The entry for the reader's locale: exact match first, then base language.
    private func pickEntry(_ list: [MultiLocaleEntry]?, readerLocale: String) -> FetchedTranslation? {
        let entries = (list ?? []).compactMap { entry -> FetchedTranslation? in
            guard let text = entry.translatedText, let language = entry.language else { return nil }
            return FetchedTranslation(language: language, translatedText: text)
        }
        if let exact = entries.first(where: { $0.language == readerLocale }) { return exact }
        let base = UIStrings.baseLanguage(readerLocale)
        return entries.first(where: { UIStrings.baseLanguage($0.language) == base })
    }

    private struct MultiLocaleResponse: Decodable {
        let translates: [MultiLocaleEntry]?
    }

    private struct MultiLocaleEntry: Decodable {
        let translatedText: String?
        let language: String?
    }

    private struct SingleResponse: Decodable {
        let translatedText: String?
    }
}
