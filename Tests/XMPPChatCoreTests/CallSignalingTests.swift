//
//  CallSignalingTests.swift
//  XMPPChatCoreTests
//
//  Wire-shape tests for 1:1 call signalling. Outgoing stanzas go through
//  toXML() and back through the real XML parser, so the round trip covers
//  what is actually sent. Incoming shapes follow web callTokenStanza.ts.
//

import XCTest
@testable import XMPPChatCore

final class CallSignalingTests: XCTestCase {

    // MARK: - Helpers

    private func base64URL(_ json: String) -> String {
        Data(json.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// A LiveKit-shaped JWT with an unverified payload (signature is ignored by the client).
    private func makeJwt(sub: String, metadata: String? = nil) -> String {
        var payload = "{\"sub\":\"\(sub)\""
        if let metadata {
            payload += ",\"metadata\":\"\(metadata.replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        payload += "}"
        return "header.\(base64URL(payload)).signature"
    }

    private func nowMs(offsetMs: Int64 = 0) -> String {
        String(Int64(Date().timeIntervalSince1970 * 1000) + offsetMs)
    }

    private func tokenStanza(
        token: String,
        room: String = "room1",
        stanzaIdValue: String?,
        kind: String? = "video",
        callId: String? = nil
    ) -> XMPPStanza {
        var dataAttributes: [String: String] = [
            "type": "call-token",
            "token": token,
            "room": room,
        ]
        if let kind { dataAttributes["kind"] = kind }
        if let callId { dataAttributes["callId"] = callId }
        var children = [XMPPStanza(name: "data", attributes: dataAttributes)]
        if let stanzaIdValue {
            children.append(XMPPStanza(name: "stanza-id", attributes: [
                "id": stanzaIdValue,
                "by": "room1@conference.test",
            ]))
        }
        return XMPPStanza(
            name: "message",
            attributes: ["type": "groupchat", "from": "room1@conference.test/alice"],
            children: children
        )
    }

    private func parse(_ stanza: XMPPStanza) -> (swallow: Bool, event: CallSignalEvent?)? {
        CallSignaling.parseIncoming(inner: stanza, outer: stanza)
    }

    // MARK: - Outgoing round trips

    func testCallInviteStanzaRoundTripsThroughXML() throws {
        let stanza = CallSignaling.buildCallInviteStanza(
            peerJid: "bob@xmpp.test",
            messageId: "call-invite-1",
            kind: .audio,
            roomBareName: "appid_room1",
            callId: ""
        )
        let parsed = try XCTUnwrap(XMPPStanzaParser.parse(stanza.toXML()))

        XCTAssertEqual(parsed.name, "message")
        XCTAssertEqual(parsed.attributes["to"], "bob@xmpp.test")
        XCTAssertEqual(parsed.attributes["type"], "chat")
        XCTAssertEqual(parsed.attributes["id"], "call-invite-1")

        let data = try XCTUnwrap(parsed.getChild("data"))
        XCTAssertEqual(data.attributes["type"], "call-invite")
        XCTAssertEqual(data.attributes["kind"], "audio")
        XCTAssertEqual(data.attributes["room"], "appid_room1")
        XCTAssertEqual(data.attributes["callId"], "")
    }

    func testCallStateStanzaRoundTripsThroughXML() throws {
        let stanza = CallSignaling.buildCallStateStanza(
            peerJid: "bob@xmpp.test",
            messageId: "call-state-9",
            state: .declined,
            roomBareName: "appid_room1",
            callId: "call-42"
        )
        let parsed = try XCTUnwrap(XMPPStanzaParser.parse(stanza.toXML()))

        XCTAssertEqual(parsed.attributes["to"], "bob@xmpp.test")
        let data = try XCTUnwrap(parsed.getChild("data"))
        XCTAssertEqual(data.attributes["type"], "call-state")
        XCTAssertEqual(data.attributes["state"], "declined")
        XCTAssertEqual(data.attributes["callId"], "call-42")
        XCTAssertEqual(data.attributes["room"], "appid_room1")
    }

    func testPeerJidAppendsHostOnlyForLocalparts() {
        XCTAssertEqual(CallSignaling.peerJid("bob", host: "xmpp.test"), "bob@xmpp.test")
        XCTAssertEqual(CallSignaling.peerJid("bob@other.test", host: "xmpp.test"), "bob@other.test")
    }

    // MARK: - Incoming call-token

    func testFreshCallTokenProducesTokenEventAndIsSwallowed() throws {
        let token = makeJwt(sub: "Roman Test", metadata: "{\"callId\":\"call-7\"}")
        let stanza = tokenStanza(token: token, stanzaIdValue: nowMs())

        let result = try XCTUnwrap(parse(stanza))
        XCTAssertTrue(result.swallow)

        guard case let .token(incoming)? = result.event else {
            return XCTFail("expected a token event, got \(String(describing: result.event))")
        }
        XCTAssertEqual(incoming.room, "room1")
        XCTAssertEqual(incoming.stanzaKind, .video)
        XCTAssertEqual(incoming.callerName, "Roman Test")
        XCTAssertEqual(incoming.jwtCallId, "call-7")
        XCTAssertNil(incoming.callId)
    }

    func testStaleCallTokenIsSwallowedWithoutEvent() throws {
        let token = makeJwt(sub: "Roman Test")
        let stanza = tokenStanza(token: token, stanzaIdValue: nowMs(offsetMs: -10_000))

        let result = try XCTUnwrap(parse(stanza))
        XCTAssertTrue(result.swallow)
        XCTAssertNil(result.event)
    }

    func testCallTokenWithoutStanzaIdIsNotFresh() throws {
        let stanza = tokenStanza(token: makeJwt(sub: "Roman Test"), stanzaIdValue: nil)
        let result = try XCTUnwrap(parse(stanza))
        XCTAssertNil(result.event)
    }

    func testCallTokenFreshnessFallsBackToOuterStanzaId() throws {
        // MUC-Sub wrapper: the stanza-id sits on the outer message, not the inner one.
        let inner = tokenStanza(token: makeJwt(sub: "Roman Test"), stanzaIdValue: nil)
        let outer = XMPPStanza(
            name: "message",
            attributes: ["from": "room1@conference.test"],
            children: [XMPPStanza(name: "stanza-id", attributes: ["id": nowMs()])]
        )
        let result = try XCTUnwrap(CallSignaling.parseIncoming(inner: inner, outer: outer))
        if case .token? = result.event {} else {
            XCTFail("expected a token event when the outer stanza-id is fresh")
        }
    }

    // MARK: - Incoming call-invite and call-state

    func testCallInviteIsSwallowedAndCarriesKind() throws {
        let stanza = XMPPStanza(
            name: "message",
            attributes: ["type": "chat", "from": "bob@xmpp.test/res"],
            children: [XMPPStanza(name: "data", attributes: [
                "type": "call-invite", "kind": "audio", "room": "room1", "callId": "c-9",
            ])]
        )
        let result = try XCTUnwrap(parse(stanza))
        XCTAssertTrue(result.swallow)
        XCTAssertEqual(result.event, .invite(room: "room1", callId: "c-9", kind: .audio))
    }

    func testBareCallStateIsSwallowedAndCarriesState() throws {
        let stanza = XMPPStanza(
            name: "message",
            attributes: ["type": "chat"],
            children: [XMPPStanza(name: "data", attributes: [
                "type": "call-state", "state": "cancelled", "callId": "c-1", "room": "room1",
            ])]
        )
        let result = try XCTUnwrap(parse(stanza))
        XCTAssertTrue(result.swallow)
        XCTAssertEqual(
            result.event,
            .state(state: "cancelled", callId: "c-1", room: "room1", callLog: nil)
        )
    }

    func testServerCallLogIsNotSwallowedSoItShowsInTheChat() throws {
        let stanza = XMPPStanza(
            name: "message",
            attributes: ["type": "groupchat", "from": "room1@conference.test/alice"],
            children: [XMPPStanza(name: "data", attributes: [
                "type": "call-state",
                "callId": "c-5",
                "durationMs": "12000",
                "callerXmppUsername": "alice@xmpp.test",
                "kind": "video",
                "isSystemMessage": "true",
            ])]
        )
        let result = try XCTUnwrap(parse(stanza))
        XCTAssertFalse(result.swallow, "call-log rows must reach the chat pipeline")

        let expected = CallLogMeta(callId: "c-5", durationMs: 12_000, kind: .video, callerXmppUsername: "alice")
        XCTAssertEqual(
            result.event,
            .state(state: "", callId: "c-5", room: "room1", callLog: expected)
        )
    }

    func testBodyOnlyCallKeywordIsSwallowed() throws {
        let stanza = XMPPStanza(
            name: "message",
            attributes: ["type": "groupchat"],
            children: [XMPPStanza(name: "body", text: "call-ended")]
        )
        let result = try XCTUnwrap(parse(stanza))
        XCTAssertTrue(result.swallow)
        XCTAssertEqual(result.event, .state(state: "ended", callId: nil, room: nil, callLog: nil))
    }

    func testOrdinaryChatMessageIsNotClassified() {
        let stanza = XMPPStanza(
            name: "message",
            attributes: ["type": "groupchat"],
            children: [XMPPStanza(name: "body", text: "hello there")]
        )
        XCTAssertNil(CallSignaling.parseIncoming(inner: stanza, outer: stanza))
    }

    // MARK: - Helpers

    func testNumericTimestampExtraction() {
        XCTAssertEqual(CallSignaling.extractNumericTimestamp("1729000000000"), 1_729_000_000_000)
        XCTAssertEqual(CallSignaling.extractNumericTimestamp("1729000000000123"), 1_729_000_000_000)
        XCTAssertEqual(CallSignaling.extractNumericTimestamp("evt-1729000000000-x"), 1_729_000_000_000)
        XCTAssertNil(CallSignaling.extractNumericTimestamp(""))
        XCTAssertNil(CallSignaling.extractNumericTimestamp(nil))
    }

    func testPeerDerivationFromOneToOneRoomName() {
        XCTAssertEqual(
            CallSignaling.derivePeerXmppUsername(bareRoomName: "alice-bob", selfXmppUsername: "alice@xmpp.test"),
            "bob"
        )
        XCTAssertEqual(
            CallSignaling.derivePeerXmppUsername(bareRoomName: "alice-bob", selfXmppUsername: "bob"),
            "alice"
        )
        XCTAssertNil(CallSignaling.derivePeerXmppUsername(bareRoomName: "a-b-c", selfXmppUsername: "a"))
        XCTAssertNil(CallSignaling.derivePeerXmppUsername(bareRoomName: "groupchat", selfXmppUsername: "a"))
    }

    func testCallerDisplayNameRejectsRawIds() {
        XCTAssertEqual(CallSignaling.callerDisplayName(fromJwt: ["sub": "Roman Test"]), "Roman Test")
        XCTAssertEqual(CallSignaling.callerDisplayName(fromJwt: ["sub": "6a2c08adef26ca2d3e1e3677"]), "")
        XCTAssertEqual(CallSignaling.callerDisplayName(fromJwt: nil), "")
    }

    func testJwtPayloadDecodesMetadataAsStringOrObject() {
        let asString = makeJwt(sub: "x", metadata: "{\"callId\":\"abc\"}")
        XCTAssertEqual(CallSignaling.callId(fromJwt: CallSignaling.decodeJwtPayload(asString)), "abc")
        XCTAssertNil(CallSignaling.decodeJwtPayload("not-a-jwt"))
    }

    // MARK: - Call log

    func testCallLogLabelsMatchWebWording() {
        let outgoingLong = CallLogMeta(callId: "1", durationMs: 12_000, kind: .video, callerXmppUsername: "alice")
        XCTAssertEqual(
            CallLogFormatter.label(for: outgoingLong, selfXmppUsername: "alice@xmpp.test"),
            "Outgoing call · 12 sec"
        )
        XCTAssertEqual(
            CallLogFormatter.label(for: outgoingLong, selfXmppUsername: "bob@xmpp.test"),
            "Incoming call · 12 sec"
        )

        let minuteAndSeconds = CallLogMeta(callId: "2", durationMs: 65_000, kind: .audio, callerXmppUsername: "bob")
        XCTAssertEqual(
            CallLogFormatter.label(for: minuteAndSeconds, selfXmppUsername: "alice"),
            "Incoming call · 1 min 5 sec"
        )

        let exactMinute = CallLogMeta(callId: "3", durationMs: 60_000, kind: .video, callerXmppUsername: "alice")
        XCTAssertEqual(CallLogFormatter.formatDuration(ms: exactMinute.durationMs), "1 min")

        let unansweredOutgoing = CallLogMeta(callId: "4", durationMs: 0, kind: .video, callerXmppUsername: "alice")
        XCTAssertEqual(CallLogFormatter.label(for: unansweredOutgoing, selfXmppUsername: "alice"), "No answer")

        let missedIncoming = CallLogMeta(callId: "5", durationMs: 0, kind: .video, callerXmppUsername: "bob")
        XCTAssertEqual(CallLogFormatter.label(for: missedIncoming, selfXmppUsername: "alice"), "Missed call")
    }

    func testCallLogMetaRoundTripsThroughCodableMessage() throws {
        var message = Message(
            id: "calllog-c-5",
            user: User(id: "u1"),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            body: CallLogFormatter.fallbackBody(for: CallLogMeta(callId: "c-5", durationMs: 12_000, kind: .video, callerXmppUsername: "alice")),
            roomJid: "room1@conference.test"
        )
        message.callLog = CallLogMeta(callId: "c-5", durationMs: 12_000, kind: .video, callerXmppUsername: "alice")

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        XCTAssertEqual(decoded.callLog, message.callLog)
        XCTAssertEqual(decoded, message)
    }

    func testMessageParserBuildsCallLogRowFromServerEntry() throws {
        let stanza = XMPPStanza(
            name: "message",
            attributes: ["type": "groupchat", "from": "room1@conference.test/alice", "id": "srv-1"],
            children: [XMPPStanza(name: "data", attributes: [
                "type": "call-state",
                "callId": "c-5",
                "durationMs": "0",
                "callerXmppUsername": "bob@xmpp.test",
                "isSystemMessage": "true",
            ])]
        )
        let data = try XCTUnwrap(MessageParser.getDataFromStanza(stanza))
        let message = MessageParser.createMessageFromData(data)

        XCTAssertEqual(message.callLog?.callId, "c-5")
        XCTAssertEqual(message.callLog?.callerXmppUsername, "bob")
        XCTAssertEqual(message.callLog?.isMissed, true)
        XCTAssertFalse(message.body.isEmpty, "call-log rows need a non-empty body to survive the chat pipeline")
    }
}
