import XCTest
@testable import XMPPChatCore

/// Tests for `XMPPCredentialRecovery` (web credentialsProvider port): forced
/// rotation when refreshTokens is on, single-flight xmpp-token, stored fallback.
@MainActor
final class XMPPCredentialRecoveryTests: NetworkTestCase {

    private var originalRefresh: (() async -> RefreshResult?)!
    private var originalFetch: ((String) async throws -> String)!

    override func setUp() async throws {
        try await super.setUp()
        originalRefresh = XMPPCredentialRecovery.shared.refreshSession
        originalFetch = XMPPCredentialRecovery.shared.fetchPassword
    }

    override func tearDown() async throws {
        XMPPCredentialRecovery.shared.refreshSession = originalRefresh
        XMPPCredentialRecovery.shared.fetchPassword = originalFetch
        try await super.tearDown()
    }

    private func setUser() {
        UserStore.shared.currentUser = User(
            id: "u1", token: "user-token", refreshToken: "refresh-1",
            xmppPassword: "stale-xmpp", xmppUsername: "alice@xmpp.test"
        )
    }

    func testRecoverFetchesFreshPasswordAndStoresIt() async {
        setUser()
        XMPPCredentialRecovery.shared.fetchPassword = { token in
            XCTAssertEqual(token, "user-token")
            return "fresh-xmpp"
        }

        let credentials = await XMPPCredentialRecovery.shared.recover()

        XCTAssertEqual(credentials?.username, "alice@xmpp.test")
        XCTAssertEqual(credentials?.password, "fresh-xmpp")
        XCTAssertEqual(UserStore.shared.currentUser?.xmppPassword, "fresh-xmpp",
                       "the fresh password is kept for the next client")
    }

    func testRotationIsForcedFirstWhenRefreshTokensEnabled() async {
        setUser()
        var config = ChatConfig()
        config.refreshTokens = RefreshTokensConfig(enabled: true, refreshFunction: {
            ("host-access", nil)
        })
        ConfigStore.shared.mergeConfig(config)
        var fetchCalled = false
        XMPPCredentialRecovery.shared.refreshSession = {
            RefreshResult(token: "rotated", refreshToken: "refresh-2", xmppPassword: "rotated-xmpp")
        }
        XMPPCredentialRecovery.shared.fetchPassword = { _ in
            fetchCalled = true
            return "unused"
        }

        let credentials = await XMPPCredentialRecovery.shared.recover()

        XCTAssertEqual(credentials?.password, "rotated-xmpp")
        XCTAssertFalse(fetchCalled, "a rotation that already returns a password skips xmpp-token")
    }

    func testStoredPasswordIsTheLastResort() async {
        setUser()
        XMPPCredentialRecovery.shared.fetchPassword = { _ in
            throw XMPPTokenAPIError.httpError(500, "down")
        }

        let credentials = await XMPPCredentialRecovery.shared.recover()

        XCTAssertEqual(credentials?.password, "stale-xmpp")
    }

    func testConcurrentFetchesShareOneRequest() async {
        setUser()
        var calls = 0
        XMPPCredentialRecovery.shared.fetchPassword = { _ in
            calls += 1
            try await Task.sleep(nanoseconds: 50_000_000)
            return "shared-xmpp"
        }

        async let first = XMPPCredentialRecovery.shared.fetchFreshPassword()
        async let second = XMPPCredentialRecovery.shared.fetchFreshPassword()
        let (a, b) = await (first, second)

        XCTAssertEqual(calls, 1)
        XCTAssertEqual(a, "shared-xmpp")
        XCTAssertEqual(b, "shared-xmpp")
    }

    func testXMPPTokenEndpointShape() async throws {
        StubURLProtocol.replies = [.json(200, ["success": true, "xmppPassword": "minted"])]

        let password = try await XMPPTokenAPI.fetchXmppPassword(token: "user-token")

        let call = onlyCall()
        XCTAssertEqual(call.method, "POST")
        XCTAssertEqual(call.url.absoluteString, "\(Self.baseURL)/users/xmpp-token")
        XCTAssertEqual(call.authorization, "user-token")
        XCTAssertEqual(password, "minted")
    }
}
