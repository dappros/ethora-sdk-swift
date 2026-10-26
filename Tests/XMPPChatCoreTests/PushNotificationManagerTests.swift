import XCTest
@testable import XMPPChatCore

/// Tests for `PushNotificationManager`: tapped-payload hand-off, token
/// registration outcomes, gateway mode, the host token hook.
@MainActor
final class PushNotificationManagerTests: NetworkTestCase {

    private let hexToken = String(repeating: "cd", count: 32)

    override func setUp() async throws {
        try await super.setUp()
        await PushNotificationManager.shared.reset()
        PendingNotificationJidStore.clearPendingJid()
    }

    override func tearDown() async throws {
        await PushNotificationManager.shared.reset()
        PendingNotificationJidStore.clearPendingJid()
        try await super.tearDown()
    }

    // MARK: - Tapped payload

    func testTappedPayloadStoresPendingRoomAndPostsNotification() {
        var received: String?
        let observer = NotificationCenter.default.addObserver(
            forName: PushNotificationManager.openRoomNotification, object: nil, queue: nil
        ) { note in
            received = note.userInfo?["roomJid"] as? String
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let jid = PushNotificationManager.shared.handlePushPayload(["jid": "room1@conference.test/nick"])

        XCTAssertEqual(jid, "room1@conference.test")
        XCTAssertEqual(received, "room1@conference.test")
        XCTAssertEqual(PendingNotificationJidStore.peekPendingBareJid(), "room1@conference.test")
    }

    func testTappedPayloadReadsNestedDataKey() {
        let jid = PushNotificationManager.shared.handlePushPayload(["data": ["chatJid": "r2@conference.test"]])
        XCTAssertEqual(jid, "r2@conference.test")
    }

    func testTappedPayloadWithoutRoomIsIgnored() {
        XCTAssertNil(PushNotificationManager.shared.handlePushPayload(["aps": ["alert": "hi"]]))
        XCTAssertNil(PendingNotificationJidStore.peekPendingBareJid())
    }

    // MARK: - Registration outcomes

    func testRegisterIsDisabledByConfig() async throws {
        var config = ChatConfig()
        config.pushNotifications = PushNotificationsConfig(enabled: false)
        ConfigStore.shared.mergeConfig(config)

        let outcome = try await PushNotificationManager.shared.registerPushToken(hexToken)

        XCTAssertEqual(outcome, .disabled)
        XCTAssertTrue(StubURLProtocol.captured.isEmpty)
    }

    func testRegisterDefersWithoutSession() async throws {
        UserStore.shared.clearUser()

        let outcome = try await PushNotificationManager.shared.registerPushToken(hexToken)

        XCTAssertEqual(outcome, .deferred)
        XCTAssertTrue(StubURLProtocol.captured.isEmpty)
    }

    func testRegisterSendsDetectedTokenType() async throws {
        StubURLProtocol.replies = [.empty(200)]

        let outcome = try await PushNotificationManager.shared.registerPushToken(hexToken)

        XCTAssertEqual(outcome, .registered)
        let call = onlyCall()
        XCTAssertEqual(call.url.absoluteString, "\(Self.baseURL)/push/subscription/app1")
        XCTAssertEqual(call.body?["tokenType"] as? String, "apns")
    }

    func testUnregisterReleasesTheRegisteredSlot() async throws {
        StubURLProtocol.replies = [.empty(200), .empty(200)]
        _ = try await PushNotificationManager.shared.registerPushToken(hexToken)

        try await PushNotificationManager.shared.unregisterPushToken(tokenType: .apns)

        XCTAssertEqual(StubURLProtocol.captured.count, 2)
        XCTAssertEqual(StubURLProtocol.captured[1].method, "DELETE")
    }

    // MARK: - Gateway mode

    func testGatewayModeWaitsForProjectName() async throws {
        var config = ChatConfig()
        config.pushNotifications = PushNotificationsConfig(apiUrl: "https://push.test.example/api/v1")
        ConfigStore.shared.mergeConfig(config)
        UserStore.shared.currentUser?.xmppUsername = "alice"

        let outcome = try await PushNotificationManager.shared.registerPushToken(hexToken)

        XCTAssertEqual(outcome, .deferred, "gateway mode needs projectName")
        XCTAssertTrue(StubURLProtocol.captured.isEmpty)
    }

    func testGatewayModeRegistersThroughGateway() async throws {
        var config = ChatConfig()
        config.pushNotifications = PushNotificationsConfig(apiUrl: "https://push.test.example/api/v1")
        config.projectName = "demo"
        config.xmppSettings = XMPPSettings(host: "xmpp.test.example")
        ConfigStore.shared.mergeConfig(config)
        UserStore.shared.currentUser?.xmppUsername = "alice"
        StubURLProtocol.replies = [.empty(201)]

        let outcome = try await PushNotificationManager.shared.registerPushToken(hexToken)

        XCTAssertEqual(outcome, .registered)
        let call = onlyCall()
        XCTAssertEqual(call.url.absoluteString, "https://push.test.example/api/v1/subscriptions")
        XCTAssertEqual(call.body?["jid"] as? String, "alice@xmpp.test.example")
        XCTAssertEqual(call.body?["projectName"] as? String, "demo")
    }

    // MARK: - Host token hook

    func testHostTokenHookRegistersReturnedTokens() async {
        var config = ChatConfig()
        config.pushNotifications = PushNotificationsConfig(getPushTokens: {
            [PushTokenRegistration(token: self.hexToken, tokenType: .apns)]
        })
        ConfigStore.shared.mergeConfig(config)
        StubURLProtocol.replies = [.empty(200)]

        await PushNotificationManager.shared.refreshRoomPushSubscriptions()

        let call = onlyCall()
        XCTAssertEqual(call.body?["registrationToken"] as? String, hexToken)
        XCTAssertEqual(call.body?["tokenType"] as? String, "apns")
    }
}

/// MUCSub stanza shape (src/networking/xmpp/subscribeToRoomMessages.xmpp.ts), round-tripped through the parser.
@MainActor
final class MUCSubStanzaTests: XCTestCase {

    func testSubscribeIQRoundTripsThroughParser() throws {
        let iq = MUCSubStanza.subscribeIQ(
            roomJID: "room1@conference.test", nick: "alice", id: "newSubscription:42"
        )

        let parsed = try XCTUnwrap(XMPPStanzaParser.parse(iq.toXML()))

        XCTAssertEqual(parsed.name, "iq")
        XCTAssertEqual(parsed.attributes["to"], "room1@conference.test")
        XCTAssertEqual(parsed.attributes["type"], "set")
        XCTAssertEqual(parsed.attributes["id"], "newSubscription:42")
        let subscribe = try XCTUnwrap(parsed.getChild("subscribe"))
        XCTAssertEqual(subscribe.attributes["xmlns"], "urn:xmpp:mucsub:0")
        XCTAssertEqual(subscribe.attributes["nick"], "alice")
        let event = try XCTUnwrap(subscribe.getChild("event"))
        XCTAssertEqual(event.attributes["node"], "urn:xmpp:mucsub:nodes:messages")
    }

    func testSubscribeIQOmitsEmptyNick() throws {
        let iq = MUCSubStanza.subscribeIQ(roomJID: "r@conference.test", nick: "", id: "newSubscription:1")
        let subscribe = try XCTUnwrap(iq.getChild("subscribe"))
        XCTAssertNil(subscribe.attributes["nick"])
    }
}
