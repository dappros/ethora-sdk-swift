import XCTest
@testable import XMPPChatCore

/// Hermetic L1 tests for `UserStore` — the singleton that owns the
/// authenticated user + access/refresh tokens. The contract pinned
/// here:
///   • `setUser(from:)` hydrates state + UserDefaults from a
///     `LoginResponse`.
///   • `updateTokens` rotates token + refresh token without disturbing
///     the rest of the user record (post-refresh flow).
///   • `clearUser` zeroes state and removes all persisted defaults so a
///     subsequent cold-start lands at the auth screen.
///   • `hasCachedUser` derivation matches `isAuthenticated && currentUser != nil && token != nil`.
///
/// The `setUser(from:)` test builds a `LoginResponse` via JSON decoding
/// so we don't need a fragile in-memory initializer for every
/// `Codable` sub-struct — that path also exercises the codable contract.
@MainActor
final class UserStoreTests: XCTestCase {

    override func setUp() async throws {
        UserStore.shared.clearUser()
    }

    override func tearDown() async throws {
        UserStore.shared.clearUser()
    }

    // MARK: - Helpers

    private func makeLoginResponse(
        userId: String = "user-1",
        firstName: String? = "Test",
        lastName: String? = "User",
        email: String? = "test@example.com",
        xmppUsername: String? = "test_user",
        xmppPassword: String? = "x-pass",
        token: String = "access.token.value",
        refreshToken: String = "refresh.token.value"
    ) -> AuthAPI.LoginResponse {
        // Building via JSON decoding keeps the test in sync with the
        // wire schema. If a field name changes server-side and the
        // model is updated, this fixture is the first thing that breaks.
        let json: [String: Any] = [
            "success": true,
            "token": token,
            "refreshToken": refreshToken,
            "user": [
                "_id": userId,
                "firstName": firstName as Any,
                "lastName": lastName as Any,
                "email": email as Any,
                "xmppUsername": xmppUsername as Any,
                "xmppPassword": xmppPassword as Any,
            ].compactMapValues { ($0 as? NSNull) == nil ? $0 : nil },
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(AuthAPI.LoginResponse.self, from: data)
    }

    // MARK: - Initial state

    func testFreshClearedStoreReportsLoggedOut() {
        // After clearUser the store must read as fully empty — no token,
        // no user, isAuthenticated = false, hasCachedUser = false.
        XCTAssertNil(UserStore.shared.currentUser)
        XCTAssertNil(UserStore.shared.token)
        XCTAssertNil(UserStore.shared.refreshToken)
        XCTAssertFalse(UserStore.shared.isAuthenticated)
        XCTAssertFalse(UserStore.shared.hasCachedUser)
    }

    // MARK: - setUser(from:)

    func testSetUserHydratesCurrentUserTokensAndAuthFlag() {
        let response = makeLoginResponse()

        UserStore.shared.setUser(from: response)

        XCTAssertEqual(UserStore.shared.currentUser?.id, "user-1")
        XCTAssertEqual(UserStore.shared.currentUser?.email, "test@example.com")
        XCTAssertEqual(UserStore.shared.currentUser?.xmppUsername, "test_user")
        XCTAssertEqual(UserStore.shared.currentUser?.xmppPassword, "x-pass",
                       "xmppPassword is the SASL credential — must round-trip from LoginResponse")
        XCTAssertEqual(UserStore.shared.token, "access.token.value")
        XCTAssertEqual(UserStore.shared.refreshToken, "refresh.token.value")
        XCTAssertTrue(UserStore.shared.isAuthenticated)
        XCTAssertTrue(UserStore.shared.hasCachedUser)
    }

    func testSetUserPersistsTokenAndRefreshTokenToUserDefaults() {
        // Persistence is the difference between "logged in until app
        // kill" and "logged in across app launches". This is the
        // smoke-test for the persistence path; the actual cold-start
        // reload happens in `init()` which we can't exercise on a
        // singleton mid-test.
        let response = makeLoginResponse(token: "persisted.access", refreshToken: "persisted.refresh")

        UserStore.shared.setUser(from: response)

        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "ethora_user_token"),
            "persisted.access"
        )
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "ethora_user_refresh_token"),
            "persisted.refresh"
        )
        XCTAssertNotNil(
            UserDefaults.standard.data(forKey: "ethora_user_data"),
            "the user record itself must be persisted as JSON"
        )
    }

    func testSetUserComposesFullNameFromFirstAndLast() {
        let response = makeLoginResponse(firstName: "Alice", lastName: "Smith")
        UserStore.shared.setUser(from: response)
        XCTAssertEqual(UserStore.shared.currentUser?.name, "Alice Smith")
        XCTAssertEqual(UserStore.shared.currentUser?.firstName, "Alice")
        XCTAssertEqual(UserStore.shared.currentUser?.lastName, "Smith")
    }

    // MARK: - updateTokens (post-refresh flow)

    func testUpdateTokensRotatesAccessAndRefreshWithoutTouchingUserRecord() {
        // Refresh path must rotate just the tokens; the user record
        // (id, email, xmppUsername/Password) is untouched. Worth
        // pinning since the backend's refresh response shape has drifted
        // historically.
        UserStore.shared.setUser(from: makeLoginResponse())
        let userBefore = UserStore.shared.currentUser

        UserStore.shared.updateTokens(token: "new.access", refreshToken: "new.refresh")

        XCTAssertEqual(UserStore.shared.token, "new.access")
        XCTAssertEqual(UserStore.shared.refreshToken, "new.refresh")
        XCTAssertEqual(UserStore.shared.currentUser, userBefore,
                       "user record must not change on token refresh")
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "ethora_user_token"),
            "new.access"
        )
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "ethora_user_refresh_token"),
            "new.refresh"
        )
    }

    // MARK: - clearUser

    func testClearUserZeroesStateAndRemovesPersistedDefaults() {
        UserStore.shared.setUser(from: makeLoginResponse())
        XCTAssertTrue(UserStore.shared.isAuthenticated, "precondition")

        UserStore.shared.clearUser()

        XCTAssertNil(UserStore.shared.currentUser)
        XCTAssertNil(UserStore.shared.token)
        XCTAssertNil(UserStore.shared.refreshToken)
        XCTAssertFalse(UserStore.shared.isAuthenticated)
        XCTAssertFalse(UserStore.shared.hasCachedUser)

        XCTAssertNil(UserDefaults.standard.string(forKey: "ethora_user_token"))
        XCTAssertNil(UserDefaults.standard.string(forKey: "ethora_user_refresh_token"))
        XCTAssertNil(UserDefaults.standard.data(forKey: "ethora_user_data"))
    }

    // MARK: - hasCachedUser derivation

    func testHasCachedUserIsFalseWhenAuthFlagOffEvenIfTokenSet() {
        // Defensive: the three components are AND'd. Flipping any one
        // off must drop hasCachedUser to false. Guards against a path
        // where a partial state slips through (e.g. token write
        // succeeds, user-data write fails).
        UserStore.shared.setUser(from: makeLoginResponse())
        UserStore.shared.isAuthenticated = false
        XCTAssertFalse(UserStore.shared.hasCachedUser)
    }
}
