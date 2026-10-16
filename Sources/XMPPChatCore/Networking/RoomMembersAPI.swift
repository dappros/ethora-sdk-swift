//
//  RoomMembersAPI.swift
//  XMPPChatCore
//
//  Single-user profile lookup with the web route fallback.
//  Mirrors src/networking/api-requests/roomMembers.api.ts (lookupUser):
//
//    1. GET /v1/apps/users/{xmppUsername}   the intended route
//    2. GET /v2/chats/users?xmppUsername=   used when the backend refuses the
//                                           user token on v1 (400/401, or a 404
//                                           that is not USER_NOT_FOUND)
//
//  A refused v1 is remembered for 10 minutes and v2 is used meanwhile, then v1
//  is probed again. 403 on v1 is a per-user answer ("forbidden") and never falls
//  back, because v2 would leak what v1 refused. Only display fields are kept.
//

import Foundation

public enum RoomMembersAPI {

    public enum Mode: String, Codable {
        case auto
        case v1
        case v2
    }

    /// Result of one lookup. `notFound` and `forbidden` are per-user answers,
    /// `error` is transient (network, 5xx).
    public enum Outcome: Equatable {
        case ok(RoomMember)
        case notFound
        case forbidden
        case error
    }

    /// How one HTTP answer is read. Pure, see `classify`.
    enum Classification: Equatable {
        case ok
        case notFound
        case forbidden
        case routeUnsupported
        case error
    }

    static let routeTTL: TimeInterval = 10 * 60

    // MARK: - Route state (pure)

    /// Remembers whether v1 is refused. Pass the current time in so tests can drive it.
    public struct RouteState: Equatable {
        public private(set) var v1UnsupportedUntil: Date?

        public init(v1UnsupportedUntil: Date? = nil) {
            self.v1UnsupportedUntil = v1UnsupportedUntil
        }

        /// Which route to call next for `mode`.
        public func route(for mode: Mode, now: Date) -> Route {
            switch mode {
            case .v1: return .v1
            case .v2: return .v2
            case .auto:
                if let until = v1UnsupportedUntil, until > now { return .v2 }
                return .v1
            }
        }

        /// Records a refused v1 route for the TTL.
        public mutating func markV1Unsupported(now: Date) {
            v1UnsupportedUntil = now.addingTimeInterval(RoomMembersAPI.routeTTL)
        }

        public mutating func reset() {
            v1UnsupportedUntil = nil
        }
    }

    public enum Route: Equatable {
        case v1
        case v2
    }

    // MARK: - Classification (pure)

    /// Reads one HTTP answer the way the web lookup does.
    static func classify(status: Int, body: String?, isV1: Bool) -> Classification {
        switch status {
        case 200..<300:
            return .ok
        case 404:
            if isUserNotFoundBody(body) { return .notFound }
            // A 404 without USER_NOT_FOUND on v1 means the route is not there.
            return isV1 ? .routeUnsupported : .notFound
        case 403:
            return .forbidden
        case 400, 401:
            return isV1 ? .routeUnsupported : .error
        default:
            return .error
        }
    }

    static func isUserNotFoundBody(_ body: String?) -> Bool {
        guard let body else { return false }
        if body.range(of: "USER_NOT_FOUND", options: .caseInsensitive) != nil { return true }
        return body.range(
            of: "user[^a-z]{0,3}not[^a-z]{0,3}found",
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    // MARK: - Payload (pure)

    /// Extracts the display fields from a v1 or v2 payload. Returns nil when
    /// nothing usable is there. Accepts `result`, `item` or `data` wrappers and a one-element array.
    public static func parseUser(json: Any) -> RoomMember? {
        guard let object = json as? [String: Any] else { return nil }

        var candidate: [String: Any]? = nil
        let wrapped = object["result"] ?? object["item"] ?? object["data"]
        if let array = wrapped as? [[String: Any]] {
            candidate = array.first
        } else if let dict = wrapped as? [String: Any] {
            candidate = dict
        }
        if candidate == nil,
           object["xmppUsername"] != nil || object["firstName"] != nil || object["lastName"] != nil {
            candidate = object
        }
        // A nested wrapper with no xmppUsername of its own: unwrap once more.
        if let inner = candidate, inner["xmppUsername"] == nil,
           let deeper = (inner["result"] ?? inner["item"]) as? [String: Any] {
            candidate = deeper
        }
        guard let user = candidate else { return nil }

        let xmppUsername = stringValue(user["xmppUsername"])
        let firstName = stringValue(user["firstName"])
        let lastName = stringValue(user["lastName"])
        let id = stringValue(user["_id"])
        guard xmppUsername != nil || firstName != nil || lastName != nil || id != nil else {
            return nil
        }
        return RoomMember(
            firstName: firstName,
            lastName: lastName,
            xmppUsername: xmppUsername,
            id: id ?? xmppUsername ?? ""
        )
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    // MARK: - Lookup

    /// Looks up one user by `appId_userId` (xmppUsername). Never throws.
    /// Routes through `routeState` (main-actor owned, shared across calls).
    @MainActor
    public static func lookupUser(
        xmppUsername: String,
        mode: Mode = .auto,
        baseURL: URL? = nil,
        now: Date = Date()
    ) async -> Outcome {
        guard let token = UserStore.shared.token, !token.isEmpty else { return .error }
        let root: URL
        do {
            root = try await AppConfig.resolveBaseURL(baseURL)
        } catch {
            return .error
        }

        let route = routeState.route(for: mode, now: now)
        if route == .v1 {
            let result = await call(v1Url(root, xmppUsername), token: token, isV1: true)
            switch result {
            case .routeUnsupported:
                if mode == .auto {
                    routeState.markV1Unsupported(now: now)
                    return await lookupViaV2(root, xmppUsername, token: token)
                }
                return .error
            case let .done(outcome):
                return outcome
            }
        }
        return await lookupViaV2(root, xmppUsername, token: token)
    }

    /// Module-level route memory. Main actor, like the stores it sits beside.
    @MainActor
    public static var routeState = RouteState()

    /// Forgets the learned route (logout, account change, tests).
    @MainActor
    public static func resetRouteState() {
        routeState.reset()
    }

    // MARK: - Internals

    private enum CallResult {
        case done(Outcome)
        case routeUnsupported
    }

    private static func v1Url(_ root: URL, _ xmppUsername: String) -> URL {
        let encoded = xmppUsername.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? xmppUsername
        return root.appendingPathComponent("apps/users/\(encoded)")
    }

    @MainActor
    private static func lookupViaV2(_ root: URL, _ xmppUsername: String, token: String) async -> Outcome {
        var components = URLComponents(url: root.appendingPathComponent("chats/users"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "xmppUsername", value: xmppUsername)]
        guard let url = components?.url else { return .error }
        switch await call(url, token: token, isV1: false) {
        case let .done(outcome):
            return outcome
        case .routeUnsupported:
            return .error
        }
    }

    private static func call(_ url: URL, token: String, isV1: Bool) async -> CallResult {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .done(.error) }
            let bodyText = String(data: data, encoding: .utf8)
            switch classify(status: http.statusCode, body: bodyText, isV1: isV1) {
            case .ok:
                guard let json = try? JSONSerialization.jsonObject(with: data),
                      let user = parseUser(json: json) else {
                    return .done(.error)
                }
                return .done(.ok(user))
            case .notFound:
                return .done(.notFound)
            case .forbidden:
                return .done(.forbidden)
            case .routeUnsupported:
                return .routeUnsupported
            case .error:
                return .done(.error)
            }
        } catch {
            return .done(.error)
        }
    }
}
