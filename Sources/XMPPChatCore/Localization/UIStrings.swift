//
//  UIStrings.swift
//  XMPPChatCore
//
//  UI caption resolution, ported from web src/i18n/strings.ts (resolveStringTable,
//  toBaseLanguage, interpolate, translateKey). A locale resolves to its base
//  language ("fr-CA" -> "fr"), missing keys fall back to English, and host
//  overrides from `config.i18n.strings` are merged on top.
//

import Foundation

public enum UIStrings {
    public static let defaultLanguage = "en"

    /// Reduce a BCP-47 locale ("fr-CA") to its lowercased base language ("fr").
    public static func baseLanguage(_ locale: String?) -> String {
        let first = (locale ?? "")
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first
            .map { String($0).trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        return first.isEmpty ? defaultLanguage : first
    }

    /// The effective table for a locale: built-in table for its base language,
    /// English for any missing key, then host overrides.
    public static func resolveTable(
        locale: String?,
        overrides: [String: String]? = nil
    ) -> [String: String] {
        let base = baseLanguage(locale)
        let table = UIStringTables.byLanguage[base] ?? UIStringTables.en
        var merged = UIStringTables.en
        for (key, value) in table {
            merged[key] = value
        }
        for (key, value) in overrides ?? [:] {
            merged[key] = value
        }
        return merged
    }

    /// Looks up `key` and replaces `{name}` placeholders from `vars`. A missing
    /// key returns the key itself, the same as web, so nothing renders blank.
    public static func translate(
        _ key: String,
        locale: String?,
        overrides: [String: String]? = nil,
        vars: [String: String]? = nil
    ) -> String {
        let table = resolveTable(locale: locale, overrides: overrides)
        return interpolate(table[key] ?? key, vars: vars)
    }

    /// Replaces `{name}` placeholders. Unknown placeholders stay as written.
    public static func interpolate(_ template: String, vars: [String: String]?) -> String {
        guard let vars = vars, !vars.isEmpty, template.contains("{") else { return template }
        var output = ""
        var index = template.startIndex
        while index < template.endIndex {
            let character = template[index]
            if character == "{", let close = template[index...].firstIndex(of: "}") {
                let name = String(template[template.index(after: index)..<close])
                if !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
                    if let value = vars[name] {
                        output += value
                    } else {
                        output += template[index...close]
                    }
                    index = template.index(after: close)
                    continue
                }
            }
            output.append(character)
            index = template.index(after: index)
        }
        return output
    }

    /// Caption lookup for SwiftUI views: uses the active interface language
    /// (`LanguagePreferences`) and the host overrides in `config.i18n`.
    @MainActor
    public static func t(_ key: String, _ vars: [String: String]? = nil) -> String {
        let i18n = ConfigStore.shared.config.i18n
        return translate(
            key,
            locale: LanguagePreferences.shared.effectiveUILocale,
            overrides: i18n?.strings,
            vars: vars
        )
    }
}
