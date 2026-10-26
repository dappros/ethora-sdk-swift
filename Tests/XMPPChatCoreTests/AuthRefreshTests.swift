import XCTest
@testable import XMPPChatCore

/// Tests for `AuthRefresh`: the single rotation point (port of web
/// authRefresh.ts). The rotation seam is replaced per test, so the error
/// table, single flight, persist-before-return and the host hook can each be
/// checked without the network.
@MainActor
final class AuthRefreshTests: NetworkTestCase {

    private var originalRotate: ((String) async throws -> RefreshResult)!
    private var originalRetryDelay: ((Int) async -> Void)!
    private var originalOnFatal: ((RefreshErrorCode) async -> Void)!
    private var fatalCodes: [RefreshErrorCode] = []

    override func setUp() async throws {
        try await super.setUp()
        originalRotate = AuthRefresh.shared.rotate
        originalRetryDelay = AuthRefresh.shared.retryDelay
        originalOnFatal = AuthRefresh.shared.onFatal
        AuthRefresh.shared.retryDelay = { _ in }
        AuthRefresh.shared.onFatal = { [weak self] code in
            self?.fatalCodes.append(code)
        }
        fatalCodes = []
    }

    override func tearDown() async throws {
        AuthRefresh.shared.rotate = originalRotate
        AuthRefresh.shared.retryDelay = originalRetryDelay
        AuthRefresh.shared.onFatal = originalOnFatal
        AuthRefresh.shared.stopProactiveRefresh()
        try await super.tearDown()
    }

    private func refreshError(_ code: String?, status: Int = 401) -> RefreshHTTPError {
        let body = code.map { try! JSONSerialization.data(withJSONObject: ["code": $0]) } ?? Data()
        return RefreshHTTPError(statusCode: status, body: body, headerCode: nil)
    }

    // MARK: - Error code parsing

    func testParserReadsEveryBodyShape() {
        let shapes: [[String: Any]] = [
            ["code": "REFRESH_TOKEN_REUSE_DETECTED"],
            ["error": ["code": "REFRESH_TOKEN_REUSE_DETECTED"]],
            ["errors": [["code": "REFRESH_TOKEN_REUSE_DETECTED"]]],
            ["error": "REFRESH_TOKEN_REUSE_DETECTED"],
            ["message": "Refresh failed: REFRESH_TOKEN_REUSE_DETECTED"]
        ]
        for shape in shapes {
            let body = try! JSONSerialization.data(withJSONObject: shape)
            XCTAssertEqual(RefreshErrorParser.code(body: body, headerCode: nil), .reuseDetected, "\(shape)")
        }
    }

    func testParserReadsHeaderWhenBodyIsSilent() {
        XCTAssertEqual(
            RefreshErrorParser.code(body: Data("Unauthorized".utf8), headerCode: "REFRESH_IN_PROGRESS"),
            .inProgress
        )
    }

    func testParserReturnsNilForUnknownCodes() {
        let body = try! JSONSerialization.data(withJSONObject: ["code": "SOMETHING_ELSE"])
        XCTAssertNil(RefreshErrorParser.code(body: body, headerCode: nil))
        XCTAssertNil(RefreshErrorParser.code(body: nil, headerCode: nil))
    }

    // MARK: - JWT expiry

    func testJWTExpirationIsReadFromPayload() {
        let token = Self.makeJWT(exp: 1_900_000_000)
        XCTAssertEqual(JWTClaims.expirationDate(ofToken: token)?.timeIntervalSince1970, 1_900_000_000)
        XCTAssertNil(JWTClaims.expirationDate(ofToken: "not-a-jwt"))
    }

    // MARK: - Persist before return, single flight

    func testRotationPersistsAllTokensBeforeReturning() async throws {
        AuthRefresh.shared.rotate = { presented in
            XCTAssertEqual(presented, "refresh-1")
            return RefreshResult(token: "new-access", refreshToken: "refresh-2",
                                 fileToken: "file-1", xmppPassword: "xmpp-1")
        }

        let result = try await AuthRefresh.shared.refresh()

        XCTAssertEqual(result.token, "new-access")
        XCTAssertEqual(UserStore.shared.token, "new-access")
        XCTAssertEqual(UserStore.shared.refreshToken, "refresh-2")
        XCTAssertEqual(UserStore.shared.currentUser?.fileToken, "file-1")
        XCTAssertEqual(UserStore.shared.currentUser?.xmppPassword, "xmpp-1")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "ethora_user_refresh_token"), "refresh-2")
    }

    func testConcurrentCallersShareOneRotation() async throws {
        var calls = 0
        AuthRefresh.shared.rotate = { _ in
            calls += 1
            try await Task.sleep(nanoseconds: 50_000_000)
            return RefreshResult(token: "shared-access", refreshToken: "refresh-2")
        }

        async let first = AuthRefresh.shared.refresh()
        async let second = AuthRefresh.shared.refresh()
        let (a, b) = try await (first, second)

        XCTAssertEqual(calls, 1, "concurrent callers share one request")
        XCTAssertEqual(a, b)
    }

    // MARK: - Error table

    func testReuseDetectedIsFatalAndRunsLogoutHook() async {
        AuthRefresh.shared.rotate = { _ in throw self.refreshError("REFRESH_TOKEN_REUSE_DETECTED") }

        do {
            _ = try await AuthRefresh.shared.refresh()
            XCTFail("expected a fatal error")
        } catch let fatal as RefreshFatalError {
            XCTAssertEqual(fatal.code, .reuseDetected)
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertEqual(fatalCodes, [.reuseDetected])
        XCTAssertEqual(UserStore.shared.refreshToken, "refresh-1", "a fatal rotation changes nothing")
    }

    func testNotFoundIsFatal() async {
        AuthRefresh.shared.rotate = { _ in throw self.refreshError("REFRESH_TOKEN_NOT_FOUND") }

        do {
            _ = try await AuthRefresh.shared.refresh()
            XCTFail("expected a fatal error")
        } catch let fatal as RefreshFatalError {
            XCTAssertEqual(fatal.code, .notFound)
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertEqual(fatalCodes, [.notFound])
    }

    func testAlreadyRotatedAdoptsNewerStoredTokens() async throws {
        AuthRefresh.shared.rotate = { presented in
            // Another path rotated while this one was in flight.
            UserStore.shared.applyRefreshResult(
                token: "other-access", refreshToken: "refresh-other",
                fileToken: nil, xmppPassword: nil
            )
            throw self.refreshError("REFRESH_TOKEN_ALREADY_ROTATED")
        }

        let result = try await AuthRefresh.shared.refresh()

        XCTAssertEqual(result.token, "other-access")
        XCTAssertEqual(result.refreshToken, "refresh-other")
        XCTAssertTrue(fatalCodes.isEmpty, "a benign race is not a logout")
    }

    func testAlreadyRotatedWithNothingNewerIsFatal() async {
        AuthRefresh.shared.rotate = { _ in throw self.refreshError("REFRESH_TOKEN_ALREADY_ROTATED") }

        do {
            _ = try await AuthRefresh.shared.refresh()
            XCTFail("expected a fatal error")
        } catch let fatal as RefreshFatalError {
            XCTAssertEqual(fatal.code, .alreadyRotated)
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertEqual(fatalCodes, [.alreadyRotated])
    }

    func testInProgressRetriesThenSucceeds() async throws {
        var attempts = 0
        var delays: [Int] = []
        AuthRefresh.shared.retryDelay = { attempt in delays.append(attempt) }
        AuthRefresh.shared.rotate = { _ in
            attempts += 1
            if attempts < 3 {
                throw self.refreshError("REFRESH_IN_PROGRESS")
            }
            return RefreshResult(token: "after-retry", refreshToken: "refresh-2")
        }

        let result = try await AuthRefresh.shared.refresh()

        XCTAssertEqual(result.token, "after-retry")
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(delays, [1, 2], "backoff grows with the attempt number")
        XCTAssertTrue(fatalCodes.isEmpty)
    }

    func testInProgressBudgetSpentIsNotFatal() async {
        AuthRefresh.shared.rotate = { _ in throw self.refreshError("REFRESH_IN_PROGRESS") }

        do {
            _ = try await AuthRefresh.shared.refresh()
            XCTFail("expected the error to pass through")
        } catch is RefreshFatalError {
            XCTFail("REFRESH_IN_PROGRESS must not log the user out")
        } catch let error as RefreshHTTPError {
            XCTAssertEqual(error.statusCode, 401)
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertTrue(fatalCodes.isEmpty)
    }

    func testServerErrorWithoutCodePassesThroughAndKeepsSession() async {
        AuthRefresh.shared.rotate = { _ in throw self.refreshError(nil, status: 500) }

        do {
            _ = try await AuthRefresh.shared.refresh()
            XCTFail("expected the error to pass through")
        } catch let error as RefreshHTTPError {
            XCTAssertEqual(error.statusCode, 500)
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertTrue(fatalCodes.isEmpty)
        XCTAssertEqual(UserStore.shared.token, "user-token", "a transient failure keeps the session")
    }

    // MARK: - Host rotation

    func testHostRotateReplacesBuiltInEndpoint() async throws {
        var builtInCalls = 0
        AuthRefresh.shared.rotate = { _ in
            builtInCalls += 1
            return RefreshResult(token: "builtin", refreshToken: "builtin-refresh")
        }
        var config = ChatConfig()
        config.refreshTokens = RefreshTokensConfig(enabled: true, rotate: {
            RefreshTokensResult(accessToken: "host-access", refreshToken: nil,
                                fileToken: "host-file", xmppPassword: "host-xmpp")
        })
        ConfigStore.shared.mergeConfig(config)

        let result = try await AuthRefresh.shared.refresh()

        XCTAssertEqual(builtInCalls, 0)
        XCTAssertEqual(result.token, "host-access")
        XCTAssertEqual(UserStore.shared.currentUser?.fileToken, "host-file")
        XCTAssertEqual(UserStore.shared.currentUser?.xmppPassword, "host-xmpp")
        XCTAssertEqual(UserStore.shared.refreshToken, "refresh-1",
                       "a host that returns no refresh token keeps the stored one")
    }

    func testHostRotateWithoutAccessTokenFails() async {
        var config = ChatConfig()
        config.refreshTokens = RefreshTokensConfig(enabled: true, rotate: {
            RefreshTokensResult(accessToken: "")
        })
        ConfigStore.shared.mergeConfig(config)

        do {
            _ = try await AuthRefresh.shared.refresh()
            XCTFail("expected an error")
        } catch let error as AuthRefreshError {
            XCTAssertEqual(error, .hostReturnedNoAccessToken)
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertTrue(fatalCodes.isEmpty)
    }
}
