//
//  CallKitAndGroupTests.swift
//  XMPPChatCoreTests
//
//  Pure parts of group calls and the CallKit bridge: room type gate, push
//  payload parsing, stable CallKit identity.
//

import XCTest
@testable import XMPPChatCore

final class CallKitAndGroupTests: XCTestCase {
    func testDefaultConfigAllowsPrivateAndGroupButNeverPublic() {
        let config = VideoCallsConfig(enabled: true, livekitUrl: "wss://lk.test")
        XCTAssertTrue(config.allowsCalls(in: .private))
        XCTAssertTrue(config.allowsCalls(in: .group))
        XCTAssertFalse(config.allowsCalls(in: .public))
        XCTAssertFalse(config.allowsCalls(in: nil))
    }

    func testPrivateOnlyConfigKeepsGroupsOut() {
        let config = VideoCallsConfig(enabled: true, livekitUrl: "wss://lk.test", allowedRoomTypes: ["private"])
        XCTAssertTrue(config.allowsCalls(in: .private))
        XCTAssertFalse(config.allowsCalls(in: .group))
    }

    func testCallingNeedsTheLiveKitUrl() {
        XCTAssertFalse(VideoCallsConfig(enabled: true, livekitUrl: "").isCallingAvailable)
        XCTAssertTrue(VideoCallsConfig(enabled: true, livekitUrl: "wss://lk.test").isCallingAvailable)
    }

    func testCallPushParsing() {
        let payload: [AnyHashable: Any] = [
            "type": "call",
            "callId": "c-1",
            "callToken": "",
            "mode": "p2p",
            "group": "false",
            "room": "abc_def@conference.test",
            "kind": "audio",
            "callerName": "Alice",
            "callerXmppUsername": "alice@xmpp.test",
        ]
        XCTAssertTrue(CallPush.isCallPush(payload))
        let push = CallPush.parse(payload)
        XCTAssertEqual(push.callId, "c-1")
        XCTAssertEqual(push.mode, .p2p)
        XCTAssertEqual(push.kind, .audio)
        XCTAssertFalse(push.isGroup)
        XCTAssertEqual(push.roomBareName, "abc_def")
        XCTAssertEqual(push.callerXmppUsername, "alice")
        XCTAssertNil(push.token)
    }

    func testGroupPushAndChatPushDifferentiation() {
        XCTAssertTrue(CallPush.parse(["type": "call", "callId": "g", "group": "true", "room": "r"]).isGroup)
        XCTAssertFalse(CallPush.isCallPush(["type": "message", "roomJid": "r@conference.test", "body": "hi"]))
    }

    @MainActor
    func testCallKitIdentityIsStablePerCallId() {
        let a = CallKitBridge.uuid(forCallId: "call-42")
        XCTAssertEqual(a, CallKitBridge.uuid(forCallId: "call-42"))
        XCTAssertNotEqual(a, CallKitBridge.uuid(forCallId: "call-43"))
        // Version 5 style: version nibble 5, variant bits 10.
        let bytes = withUnsafeBytes(of: a.uuid) { Array($0) }
        XCTAssertEqual(bytes[6] >> 4, 5)
        XCTAssertEqual(bytes[8] >> 6, 0b10)
    }
}
