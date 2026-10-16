//
//  AuthRefresh.swift
//  XMPPChatCore
//
//  The single refresh-token rotation point for the SDK. Ported from web
//  src/networking/authRefresh.ts and RN src/networking/authRefresh.ts.
//
//  The backend rotates the refresh token on every successful
//  /users/login/refresh and treats a re-presented (already rotated) token
//  as theft. So: rotations are single-flight, the new pair is persisted
//  before the caller resumes, and the error codes are handled as the
//  table below says. Only a RefreshFatalError means "log the user out".
//
//    REFRESH_IN_PROGRESS            retry up to 3 times (300 * attempt + 0..150 ms),
//                                   then adopt the stored tokens if they are newer
//    REFRESH_TOKEN_ALREADY_ROTATED  adopt the stored tokens if they are newer, else fatal
//    REFRESH_TOKEN_REUSE_DETECTED   fatal
//    REFRESH_TOKEN_NOT_FOUND        fatal
//    anything else                  passed through, the session is left alone
//

import Foundation

// MARK: - Models

public enum RefreshErrorCode: String, Codable, Equatable {
    case inProgress = "REFRESH_IN_PROGRESS"
    case alreadyRotated = "REFRESH_TOKEN_ALREADY_ROTATED"
    case reuseDetected = "REFRESH_TOKEN_REUSE_DETECTED"
    case notFound = "REFRESH_TOKEN_NOT_FOUND"
}

/// Tokens returned by a rotation. `fileToken` and `xmppPassword` are
/// optional, the backend sends them only sometimes.
public struct RefreshResult: Equatable {
    public let token: String
    public let refreshToken: String
    public let fileToken: String?
    public let xmppPassword: String?

    public init(token: String, refreshToken: String, fileToken: String? = nil, xmppPassword: String? = nil) {
        self.token = token
        self.refreshToken = refreshToken
        self.fileToken = fileToken
        self.xmppPassword = xmppPassword
    }
}

/// The session is genuinely dead. The caller must log out
/// (`AuthRefresh` already runs the logout hook before throwing this).
public struct RefreshFatalError: Error, LocalizedError, Equatable {
    public let code: RefreshErrorCode

    public init(code: RefreshErrorCode) {
        self.code = code
    }

    public var errorDescription: String? {
        "Refresh failed: \(code.rawValue)"
    }
}

/// A non-2xx answer from /users/login/refresh. Carries what the error
/// code parser needs: the body and the `x-error-code` header.
public struct RefreshHTTPError: Error, LocalizedError {
    public let statusCode: Int
    public let body: Data
    public let headerCode: String?

    public init(statusCode: Int, body: Data, headerCode: String?) {
        self.statusCode = statusCode
        self.body = body
        self.headerCode = headerCode
    }

    public var errorDescription: String? {
        "HTTP \(statusCode): \(RESTTransport.bodyText(body))"
    }
}

public enum AuthRefreshError: Error, LocalizedError, Equatable {
    /// Nothing to rotate: no refresh token in memory.
    case missingRefreshToken
    /// A host `refreshFunction` returned without an access token.
    case hostReturnedNoAccessToken

    public var errorDescription: String? {
        switch self {
        case .missingRefreshToken:
            return "Refresh token is missing"
        case .hostReturnedNoAccessToken:
            return "Custom refresh function did not return an access token"
        }
    }
}

// MARK: - Error code parsing

public enum RefreshErrorParser {
    private static let knownCodes: [RefreshErrorCode] = [
        .inProgress, .alreadyRotated, .reuseDetected, .notFound
    ]

    /// All four codes arrive as HTTP 401, so the code in the body (or the
    /// `x-error-code` header) is the only signal. Probes the same shapes
    /// as the web and RN parsers: `code`, `error.code`, `errors[0].code`,
    /// `error`, `message`, then the header. The first known code wins.
    public static func code(body: Data?, headerCode: String?) -> RefreshErrorCode? {
        var candidates: [String] = []
        if let body, let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            candidates.append(json["code"] as? String ?? "")
            if let error = json["error"] as? [String: Any] {
                candidates.append(error["code"] as? String ?? "")
            }
            if let errors = json["errors"] as? [[String: Any]], let first = errors.first {
                candidates.append(first["code"] as? String ?? "")
            }
            candidates.append(json["error"] as? String ?? "")
            candidates.append(json["message"] as? String ?? "")
        }
        candidates.append(headerCode ?? "")

        for candidate in candidates where !candidate.isEmpty {
            if let match = knownCodes.first(where: { candidate.contains($0.rawValue) }) {
                return match
            }
        }
        return nil
    }
}

// MARK: - JWT expiry

public enum JWTClaims {
    /// The `exp` claim of a JWT as a date. The signature is not checked:
    /// this is used only to time a refresh, the backend still decides.
    public static func expirationDate(ofToken token: String) -> Date? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64 += "="
        }
        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = object["exp"] as? NSNumber else {
            return nil
        }
        return Date(timeIntervalSince1970: exp.doubleValue)
    }
}

// MARK: - AuthRefresh

@MainActor
public final class AuthRefresh {
    public static let shared = AuthRefresh()

    /// Seconds before the access token's `exp` at which the proactive refresh fires.
    public static let proactiveMarginSeconds: TimeInterval = 120
    /// Floor for the proactive delay, so a short-lived token cannot cause a refresh loop.
    static let minimumProactiveDelay: TimeInterval = 30
    /// `refreshQuietly` skips a rotation that happened this recently, unless forced.
    static let quietMinInterval: TimeInterval = 5 * 60
    static let inProgressMaxAttempts = 3

    /// Rotates one refresh token against the backend. Tests replace it.
    var rotate: (String) async throws -> RefreshResult = { presented in
        try await AuthAPI.refreshSession(refreshToken: presented)
    }

    /// Waits before a REFRESH_IN_PROGRESS retry. Tests replace it with a no-op.
    var retryDelay: (Int) async -> Void = { attempt in
        let milliseconds = 300 * attempt + Int.random(in: 0...150)
        try? await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
    }

    /// Runs once when the session is dead (REUSE_DETECTED, NOT_FOUND, or a
    /// stale ALREADY_ROTATED). The default is the hard logout.
    var onFatal: (RefreshErrorCode) async -> Void = { _ in
        await SessionRecoveryManager.shared.forceLogout()
    }

    private var inflight: Task<RefreshResult, Error>?
    private var lastRotationAt: Date?
    private var proactiveTask: Task<Void, Never>?

    private init() {}

    // MARK: - Rotation

    /// Rotate the tokens. Concurrent callers share one rotation. Throws
    /// `RefreshFatalError` when the session is dead, and any other error
    /// (network, 5xx, a 401 without a known code) when it should be kept.
    /// - Parameter presentedRefreshToken: rotate this token instead of the
    ///   stored one. Only for bootstrap; adoption of stored tokens is then skipped.
    public func refresh(presentedRefreshToken: String? = nil) async throws -> RefreshResult {
        if let inflight {
            return try await inflight.value
        }
        let task = Task<RefreshResult, Error> {
            try await self.performRefresh(explicit: presentedRefreshToken)
        }
        inflight = task
        defer {
            if inflight == task {
                inflight = nil
            }
        }
        return try await task.value
    }

    /// Never throws. Returns nil when skipped (rotated in the last 5 minutes,
    /// unless `force`) or when the rotation failed.
    public func refreshQuietly(force: Bool = false) async -> RefreshResult? {
        if !force, let last = lastRotationAt,
           Date().timeIntervalSince(last) < Self.quietMinInterval {
            return nil
        }
        do {
            return try await refresh()
        } catch {
            print("[AuthRefresh] background refresh failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Proactive refresh

    /// Schedules a rotation `proactiveMarginSeconds` before the access token
    /// expires. Runs only when `refreshTokens.enabled` is true. Called after
    /// every successful rotation and at chat startup.
    public func scheduleProactiveRefresh() {
        proactiveTask?.cancel()
        proactiveTask = nil
        guard ConfigStore.shared.config.refreshTokens?.enabled == true else { return }
        guard let token = UserStore.shared.token,
              let expiry = JWTClaims.expirationDate(ofToken: token) else { return }

        let delay = max(expiry.timeIntervalSinceNow - Self.proactiveMarginSeconds, Self.minimumProactiveDelay)
        proactiveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            _ = await self.refreshQuietly(force: true)
        }
    }

    /// Cancels the proactive timer (logout).
    public func stopProactiveRefresh() {
        proactiveTask?.cancel()
        proactiveTask = nil
    }

    // MARK: - Internals

    private func performRefresh(explicit: String?) async throws -> RefreshResult {
        // A configured host function wins over the built-in endpoint, even
        // over an explicit token: the host may own its refresh token.
        if let rotateWithHost = hostRotation() {
            let result = try await rotateWithHost()
            persist(result)
            return result
        }

        var attempt = 1
        while true {
            let presented = explicit ?? UserStore.shared.refreshToken ?? ""
            guard !presented.isEmpty else {
                // Deliberately not fatal: a missing token during bootstrap must not end a session still loading.
                throw AuthRefreshError.missingRefreshToken
            }

            do {
                let result = try await rotate(presented)
                persist(result)
                return result
            } catch let error as RefreshHTTPError {
                guard let code = RefreshErrorParser.code(body: error.body, headerCode: error.headerCode) else {
                    throw error
                }
                switch code {
                case .inProgress:
                    if attempt < Self.inProgressMaxAttempts {
                        await retryDelay(attempt)
                        attempt += 1
                        continue
                    }
                    if explicit == nil, let adopted = adoptStoredIfNewer(than: presented) {
                        return adopted
                    }
                    throw error
                case .alreadyRotated:
                    if explicit == nil, let adopted = adoptStoredIfNewer(than: presented) {
                        return adopted
                    }
                    let fatalError = await fatal(code)
                    throw fatalError
                case .reuseDetected, .notFound:
                    let fatalError = await fatal(code)
                    throw fatalError
                }
            }
        }
    }

    /// The host's rotation, normalised to `RefreshResult`, or nil when the
    /// host configured none. Without a new refresh token from the host the
    /// stored one is kept (non-rotating hosts).
    private func hostRotation() -> (() async throws -> RefreshResult)? {
        guard let config = ConfigStore.shared.config.refreshTokens else { return nil }
        if let rotateHost = config.rotate {
            return {
                let host = try await rotateHost()
                guard !host.accessToken.isEmpty else {
                    throw AuthRefreshError.hostReturnedNoAccessToken
                }
                return RefreshResult(
                    token: host.accessToken,
                    refreshToken: host.refreshToken ?? UserStore.shared.refreshToken ?? "",
                    fileToken: host.fileToken,
                    xmppPassword: host.xmppPassword
                )
            }
        }
        if let legacy = config.refreshFunction {
            return {
                let host = try await legacy()
                guard !host.accessToken.isEmpty else {
                    throw AuthRefreshError.hostReturnedNoAccessToken
                }
                return RefreshResult(
                    token: host.accessToken,
                    refreshToken: host.refreshToken ?? UserStore.shared.refreshToken ?? "",
                    fileToken: nil,
                    xmppPassword: nil
                )
            }
        }
        return nil
    }

    /// Persist before returning, so the rotated refresh token is never lost.
    private func persist(_ result: RefreshResult) {
        UserStore.shared.applyRefreshResult(
            token: result.token,
            refreshToken: result.refreshToken,
            fileToken: result.fileToken,
            xmppPassword: result.xmppPassword
        )
        lastRotationAt = Date()
        scheduleProactiveRefresh()
    }

    /// Another path rotated while this one was in flight: use its tokens.
    private func adoptStoredIfNewer(than presented: String) -> RefreshResult? {
        let store = UserStore.shared
        guard let stored = store.refreshToken, !stored.isEmpty, stored != presented,
              let token = store.token, !token.isEmpty else {
            return nil
        }
        return RefreshResult(
            token: token,
            refreshToken: stored,
            fileToken: store.currentUser?.fileToken,
            xmppPassword: store.currentUser?.xmppPassword
        )
    }

    private func fatal(_ code: RefreshErrorCode) async -> RefreshFatalError {
        await onFatal(code)
        return RefreshFatalError(code: code)
    }
}
