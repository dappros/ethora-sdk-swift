//
//  SecureFileURL.swift
//  XMPPChatCore
//
//  Translated from helpers/secureFileUrl.ts (appendFileToken, withoutFileToken, isSecureFileUrl)
//

import Foundation

/// Files uploaded through `/v2/files/secure` are served from a `secure-files.*` host, and every download is gated
/// by chat membership: the server needs `?ft=<fileToken>` to identify the requester. The token is personal, so it
/// is appended when a URL is loaded, never stored in the stanza or in a cached message.
public enum SecureFileURL {
    /// Query parameter the file server reads the token from.
    public static let queryName = "ft"

    private static let secureHostPrefix = "secure-files."

    /// True for a URL on the secure files host. Public (`v1`) file URLs are not secure and never get a token.
    public static func isSecure(_ raw: String?) -> Bool {
        guard let raw = raw, let host = URLComponents(string: raw)?.host else { return false }
        return host.hasPrefix(secureHostPrefix)
    }

    /// `raw` with `ft=<fileToken>` set. Returns `raw` unchanged when there is no token or the URL is not secure.
    public static func appendingFileToken(_ raw: String?, fileToken: String?) -> String {
        guard let raw = raw, !raw.isEmpty else { return "" }
        guard let fileToken = fileToken, !fileToken.isEmpty,
              isSecure(raw),
              var components = URLComponents(string: raw) else {
            return raw
        }
        var items = (components.queryItems ?? []).filter { $0.name != queryName }
        items.append(URLQueryItem(name: queryName, value: fileToken))
        components.queryItems = items
        return components.url?.absoluteString ?? raw
    }

    /// `raw` without any `ft` parameter, for comparing two references to the same file.
    public static func removingFileToken(_ raw: String?) -> String {
        guard let raw = raw, !raw.isEmpty else { return "" }
        guard var components = URLComponents(string: raw), components.queryItems != nil else {
            return raw
        }
        let items = (components.queryItems ?? []).filter { $0.name != queryName }
        components.queryItems = items.isEmpty ? nil : items
        return components.url?.absoluteString ?? raw
    }

    /// `raw` with the token of `fileToken` applied, as a `URL` ready for `AsyncImage`, `AVPlayer` or `URLSession`.
    /// Falls back to percent-encoding the query when the raw string is not a valid URL.
    public static func url(_ raw: String?, fileToken: String?) -> URL? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        let resolved = appendingFileToken(trimmed, fileToken: fileToken)
        if let direct = URL(string: resolved), direct.scheme != nil {
            return direct
        }
        if let encoded = resolved.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let encodedURL = URL(string: encoded),
           encodedURL.scheme != nil {
            return encodedURL
        }
        return nil
    }

    /// `url(_:fileToken:)` with the token of the signed-in user, read on the main actor.
    @MainActor
    public static func currentURL(_ raw: String?) -> URL? {
        url(raw, fileToken: UserStore.shared.fileToken)
    }
}
