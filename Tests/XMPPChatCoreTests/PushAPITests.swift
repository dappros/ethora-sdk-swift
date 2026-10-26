import XCTest
@testable import XMPPChatCore

/// Wire-shape tests for `PushAPI` (RN push.api.ts, same endpoints web uses).
/// The stub transport records every request, so each test asserts the
/// method, URL, Authorization header and JSON body the backend receives.
@MainActor
final class PushAPITests: NetworkTestCase {

    private let hexToken = String(repeating: "ab", count: 32) // 64 hex characters

    // MARK: - Token type detection

    func testTokenTypeDetectionMatchesRN() {
        XCTAssertEqual(PushTokenType.detect(hexToken), .apns)
        XCTAssertEqual(PushTokenType.detect(String(repeating: "f", count: 63)), .fcm,
                       "63 hex characters is below the apns length")
        XCTAssertEqual(PushTokenType.detect("ExponentPushToken[abc123]"), .expo)
        XCTAssertEqual(PushTokenType.detect("dGhpcyBpcyBhIGZjbSB0b2tlbg:APA91bH"), .fcm)
    }

    // MARK: - Direct registration

    func testRegisterSendsTokenTypeAndRawAuthorization() async throws {
        StubURLProtocol.replies = [.empty(200)]

        try await PushAPI.registerPushSubscription(
            appId: "app1",
            registrationToken: hexToken,
            tokenType: .apns,
            deviceType: .ios,
            authToken: "explicit-token"
        )

        let call = onlyCall()
        XCTAssertEqual(call.method, "POST")
        XCTAssertEqual(call.url.absoluteString, "\(Self.baseURL)/push/subscription/app1")
        XCTAssertEqual(call.authorization, "explicit-token", "the token is sent raw, not as Bearer")
        XCTAssertEqual(call.body?["registrationToken"] as? String, hexToken)
        XCTAssertEqual(call.body?["deviceType"] as? String, "ios")
        XCTAssertEqual(call.body?["tokenType"] as? String, "apns")
    }

    func testRegisterRetriesWithoutTokenTypeWhenBackendSaysNotAllowed() async throws {
        StubURLProtocol.replies = [
            .json(422, ["error": "tokenType is not allowed"]),
            .empty(200)
        ]

        try await PushAPI.registerPushSubscription(
            appId: "app1",
            registrationToken: "fcm-token-1",
            tokenType: .fcm,
            deviceType: .ios,
            authToken: "explicit-token"
        )

        XCTAssertEqual(StubURLProtocol.captured.count, 2)
        let retry = StubURLProtocol.captured[1].body ?? [:]
        XCTAssertEqual(Set(retry.keys), ["registrationToken", "deviceType"],
                       "the retry drops tokenType entirely")
        XCTAssertEqual(retry["registrationToken"] as? String, "fcm-token-1")
    }

    func testExpoTokenIsNotDowngraded() async {
        StubURLProtocol.replies = [.json(422, ["error": "tokenType is not allowed"])]

        do {
            try await PushAPI.registerPushSubscription(
                appId: "app1",
                registrationToken: "ExponentPushToken[abc]",
                tokenType: .expo,
                deviceType: .ios,
                authToken: "explicit-token"
            )
            XCTFail("expected the refusal to surface")
        } catch let error as PushAPIError {
            guard case .httpError(let code, let body) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertEqual(code, 422)
            XCTAssertEqual(body, "tokenType is not allowed")
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertEqual(StubURLProtocol.captured.count, 1, "no retry for expo")
    }

    func testRegisterReportsBackendErrorMessage() async {
        StubURLProtocol.replies = [.json(500, ["error": "boom"])]

        do {
            try await PushAPI.registerPushSubscription(
                appId: "app1", registrationToken: hexToken, tokenType: .apns,
                deviceType: .ios, authToken: "explicit-token"
            )
            XCTFail("expected an error")
        } catch let error as PushAPIError {
            XCTAssertEqual(error.errorDescription, "HTTP 500: boom")
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testRegisterRotatesOnceOn401WhenUsingStoredToken() async throws {
        let rotations = RotationRecorder()
        let original = AuthRefresh.shared.rotate
        AuthRefresh.shared.rotate = { presented in
            rotations.record(presented)
            return RefreshResult(token: "rotated-token", refreshToken: "refresh-2")
        }
        defer { AuthRefresh.shared.rotate = original }
        StubURLProtocol.replies = [.json(401, ["error": "expired"]), .empty(200)]

        try await PushAPI.registerPushSubscription(
            appId: "app1", registrationToken: hexToken, tokenType: .apns, deviceType: .ios
        )

        XCTAssertEqual(StubURLProtocol.captured.count, 2)
        XCTAssertEqual(StubURLProtocol.captured[0].authorization, "user-token")
        XCTAssertEqual(StubURLProtocol.captured[1].authorization, "rotated-token")
        XCTAssertEqual(rotations.presented, ["refresh-1"])
        XCTAssertEqual(UserStore.shared.token, "rotated-token")
    }

    func testExplicitTokenIsNotRotatedOn401() async {
        StubURLProtocol.replies = [.json(401, ["error": "expired"])]

        do {
            try await PushAPI.registerPushSubscription(
                appId: "app1", registrationToken: hexToken, tokenType: .apns,
                deviceType: .ios, authToken: "explicit-token"
            )
            XCTFail("expected an error")
        } catch {
            // expected
        }
        XCTAssertEqual(StubURLProtocol.captured.count, 1, "an explicit token is never rotated behind the caller's back")
    }

    // MARK: - Release

    func testReleaseSendsDeleteWithRegistrationToken() async throws {
        StubURLProtocol.replies = [.empty(200)]

        try await PushAPI.releasePushSubscription(
            appId: "app1", registrationToken: hexToken, authToken: "explicit-token"
        )

        let call = onlyCall()
        XCTAssertEqual(call.method, "DELETE")
        XCTAssertEqual(call.url.absoluteString, "\(Self.baseURL)/push/subscription/app1")
        XCTAssertEqual(call.body?["registrationToken"] as? String, hexToken)
    }

    func testReleaseFallsBackToUsersEndpointsOn404() async throws {
        StubURLProtocol.replies = [.empty(404), .empty(200)]

        try await PushAPI.releasePushSubscription(
            appId: "app1", registrationToken: "fcm-token-2", authToken: "explicit-token"
        )

        XCTAssertEqual(StubURLProtocol.captured.count, 2)
        let fallback = StubURLProtocol.captured[1]
        XCTAssertEqual(fallback.method, "DELETE")
        XCTAssertEqual(fallback.url.absoluteString, "\(Self.baseURL)/users/endpoints")
        XCTAssertEqual(fallback.body?["endpoint"] as? String, "fcm-token-2")
    }

    func testReleaseSurfacesOtherFailuresWithoutFallback() async {
        StubURLProtocol.replies = [.json(500, ["error": "down"])]

        do {
            try await PushAPI.releasePushSubscription(
                appId: "app1", registrationToken: hexToken, authToken: "explicit-token"
            )
            XCTFail("expected an error")
        } catch {
            // expected
        }
        XCTAssertEqual(StubURLProtocol.captured.count, 1)
    }

    // MARK: - Gateway

    func testGatewayRegistrationSendsBearerAndPayload() async throws {
        StubURLProtocol.replies = [.empty(201)]

        try await PushAPI.subscribeToPushGateway(
            apiURL: "https://push.test.example/api/v1/",
            registrationToken: "fcm-token-3",
            deviceType: .ios,
            jid: "alice@xmpp.test.example",
            projectName: "demo",
            authToken: "user-token"
        )

        let call = onlyCall()
        XCTAssertEqual(call.method, "POST")
        XCTAssertEqual(call.url.absoluteString, "https://push.test.example/api/v1/subscriptions",
                       "trailing slash on apiUrl is trimmed")
        XCTAssertEqual(call.authorization, "Bearer user-token")
        XCTAssertEqual(call.body?["projectName"] as? String, "demo")
        XCTAssertEqual(call.body?["registrationToken"] as? String, "fcm-token-3")
        XCTAssertEqual(call.body?["deviceType"] as? String, "ios")
        XCTAssertEqual(call.body?["jid"] as? String, "alice@xmpp.test.example")
    }

    func testGatewayJIDIsBuiltFromUsernameAndHost() {
        XCTAssertEqual(PushAPI.gatewayJID(username: "alice", host: "xmpp.test.example"),
                       "alice@xmpp.test.example")
        XCTAssertEqual(PushAPI.gatewayJID(username: "alice@other.test", host: "xmpp.test.example"),
                       "alice@other.test", "a username that already has a domain is kept")
    }
}

/// Records what the refresh seam was asked to rotate.
@MainActor
final class RotationRecorder {
    private(set) var presented: [String] = []

    func record(_ token: String) {
        presented.append(token)
    }
}
