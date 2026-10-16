import XCTest
@testable import XMPPChatCore

/// Pure-logic tests for the rooms and events parity port. Not run in this
/// session (the coordinator compiles and runs the suite once on the integration branch).
final class RoomsEventsParityTests: XCTestCase {

    // MARK: - Helpers

    private func member(_ username: String, id: String = "id") -> RoomMember {
        RoomMember(firstName: "F", lastName: "L", xmppUsername: username, id: id)
    }

    private func room(usersCnt: Int, members: [RoomMember], type: RoomType? = .public) -> Room {
        Room(
            id: "r1",
            jid: "chat_r1@conf.test",
            name: "Room",
            title: "Room",
            usersCnt: usersCnt,
            members: members,
            type: type
        )
    }

    private func headline(from: String, eventAttrs: [String: String]) -> XMPPStanza {
        var attrs = eventAttrs
        attrs["xmlns"] = EthoraEvents.xmlns
        return XMPPStanza(
            name: "message",
            attributes: ["from": from, "type": "headline"],
            children: [XMPPStanza(name: "ethora-event", attributes: attrs)]
        )
    }

    private func json(_ text: String) -> Any {
        try! JSONSerialization.jsonObject(with: Data(text.utf8))
    }

    // MARK: - ethora-event: carrier and trust

    func testCarrierFindsDirectHeadlineAndMucSubWrapper() {
        let direct = headline(from: "admin@xmpp.test", eventAttrs: ["type": "chat-meta-updated"])
        XCTAssertNotNil(EthoraEvents.carrier(in: direct))

        let inner = headline(from: "admin@xmpp.test", eventAttrs: ["type": "chat-meta-updated"])
        let wrapped = XMPPStanza(
            name: "message",
            attributes: ["from": "room@conf.test"],
            children: [
                XMPPStanza(
                    name: "event",
                    attributes: ["xmlns": EthoraEvents.mucSubEventNS],
                    children: [
                        XMPPStanza(name: "items", children: [
                            XMPPStanza(name: "item", children: [inner]),
                        ]),
                    ]
                ),
            ]
        )
        XCTAssertNotNil(EthoraEvents.carrier(in: wrapped))
    }

    func testCarrierIgnoresNonHeadline() {
        let chat = XMPPStanza(
            name: "message",
            attributes: ["from": "admin@xmpp.test", "type": "chat"],
            children: [XMPPStanza(name: "ethora-event", attributes: ["xmlns": EthoraEvents.xmlns])]
        )
        XCTAssertNil(EthoraEvents.carrier(in: chat))
    }

    func testTrustedSenderRules() {
        XCTAssertTrue(EthoraEvents.isTrustedSender(from: "admin@xmpp.test", ownDomain: "xmpp.test", pinned: nil))
        // resource means a user or occupant stanza, never trusted
        XCTAssertFalse(EthoraEvents.isTrustedSender(from: "admin@xmpp.test/res", ownDomain: "xmpp.test", pinned: nil))
        // another domain, including the conference host
        XCTAssertFalse(EthoraEvents.isTrustedSender(from: "admin@other.test", ownDomain: "xmpp.test", pinned: nil))
        XCTAssertFalse(EthoraEvents.isTrustedSender(from: "room@conference.xmpp.test", ownDomain: "xmpp.test", pinned: nil))
        // pinned senders: localpart or full jid
        XCTAssertTrue(EthoraEvents.isTrustedSender(from: "admin@xmpp.test", ownDomain: "xmpp.test", pinned: ["admin"]))
        XCTAssertTrue(EthoraEvents.isTrustedSender(from: "admin@xmpp.test", ownDomain: "xmpp.test", pinned: ["admin@xmpp.test"]))
        XCTAssertFalse(EthoraEvents.isTrustedSender(from: "bob@xmpp.test", ownDomain: "xmpp.test", pinned: ["admin"]))
        // no own domain known: refuse
        XCTAssertFalse(EthoraEvents.isTrustedSender(from: "admin@xmpp.test", ownDomain: "", pinned: nil))
    }

    func testDomainOfJID() {
        XCTAssertEqual(EthoraEvents.domain(ofJID: "alice@XMPP.test/phone"), "xmpp.test")
        XCTAssertEqual(EthoraEvents.domain(ofJID: ""), "")
    }

    // MARK: - ethora-event: keys and parsing

    func testSafeEventKey() {
        XCTAssertTrue(EthoraEvents.isSafeEventKey("app1_user2", sessionAppId: "app1"))
        XCTAssertTrue(EthoraEvents.isSafeEventKey("app1_user2", sessionAppId: nil))
        XCTAssertFalse(EthoraEvents.isSafeEventKey("app2_user2", sessionAppId: "app1"))
        XCTAssertFalse(EthoraEvents.isSafeEventKey("nounderscore", sessionAppId: nil))
        XCTAssertFalse(EthoraEvents.isSafeEventKey("app1__", sessionAppId: nil))
        XCTAssertFalse(EthoraEvents.isSafeEventKey("app1_us/er", sessionAppId: nil))
        XCTAssertFalse(EthoraEvents.isSafeEventKey(String(repeating: "a", count: 129) + "_b", sessionAppId: nil))
        XCTAssertFalse(EthoraEvents.isSafeEventKey(nil, sessionAppId: nil))
    }

    func testParseUserProfileAndChatMeta() {
        let profile = headline(from: "admin@xmpp.test", eventAttrs: [
            "type": "user-profile-updated", "xmppUsername": "app1_u1", "appId": "app1",
        ])
        XCTAssertEqual(
            EthoraEvents.parse(carrier: profile, sessionAppId: "app1"),
            .userProfileUpdated(xmppUsername: "app1_u1")
        )

        let meta = headline(from: "admin@xmpp.test", eventAttrs: [
            "type": "chat-meta-updated", "chatName": "app1_r1",
        ])
        XCTAssertEqual(
            EthoraEvents.parse(carrier: meta, sessionAppId: "app1"),
            .chatMetaUpdated(chatName: "app1_r1")
        )
    }

    func testParseRejectsAppIdMismatchUnknownTypeAndUnsafeKey() {
        let wrongApp = headline(from: "admin@xmpp.test", eventAttrs: [
            "type": "chat-meta-updated", "chatName": "app1_r1", "appId": "app9",
        ])
        XCTAssertNil(EthoraEvents.parse(carrier: wrongApp, sessionAppId: "app1"))

        let unknown = headline(from: "admin@xmpp.test", eventAttrs: ["type": "something-else"])
        XCTAssertNil(EthoraEvents.parse(carrier: unknown, sessionAppId: "app1"))

        let unsafe = headline(from: "admin@xmpp.test", eventAttrs: [
            "type": "user-profile-updated", "xmppUsername": "app9_u1",
        ])
        XCTAssertNil(EthoraEvents.parse(carrier: unsafe, sessionAppId: "app1"))
    }

    func testBackoffSchedule() {
        XCTAssertEqual(EthoraEvents.backoff(forFailureCount: 1), 5)
        XCTAssertEqual(EthoraEvents.backoff(forFailureCount: 2), 30)
        XCTAssertEqual(EthoraEvents.backoff(forFailureCount: 3), 120)
        XCTAssertEqual(EthoraEvents.backoff(forFailureCount: 9), 120)
    }

    func testMetaPatchRefusesBadPrivateTitleAndNeverLowersUsersCnt() {
        let privateRoom = room(usersCnt: 5, members: [member("a"), member("b")], type: .private)
        let apiRoom = try! JSONDecoder().decode(ApiRoom.self, from: Data(
            #"{"name":"app1_r1","type":"private","title":"deleted user","members":[]}"#.utf8
        ))
        let patch = EthoraEvents.metaPatch(apiRoom: apiRoom, current: privateRoom)
        XCTAssertNil(patch.title, "a deleted-peer title must not overwrite a private chat title")
        XCTAssertEqual(patch.usersCnt, 5, "usersCnt never goes down")
        XCTAssertNil(patch.members, "members are not touched by a chat-meta refresh")
    }

    func testPatchedMembersAppliesNamesOnlyWhenChanged() {
        let members = [member("app1_u1"), member("app1_u2")]
        let user = RoomMember(firstName: "New", lastName: "Name", xmppUsername: "app1_u1", id: "u1")
        let next = EthoraEvents.patchedMembers(members, xmppUsername: "app1_u1", user: user)
        XCTAssertEqual(next?.first?.firstName, "New")
        XCTAssertEqual(next?.last, members.last)
        XCTAssertNil(EthoraEvents.patchedMembers(next ?? members, xmppUsername: "app1_u1", user: user))
    }

    // MARK: - Membership

    func testMessageJoinAppendsAndKnownJoinIsNoop() {
        let r = room(usersCnt: 1, members: [member("app1_a")])
        let joined = RoomMembership.messageUpdate(room: r, xmppUsername: "app1_b", memberJid: "app1_b@xmpp.test", affiliation: "member")
        XCTAssertEqual(joined, .set(members: [r.members![0], RoomMember(firstName: "", lastName: "", xmppUsername: "app1_b", id: "", jid: "app1_b@xmpp.test")], usersCnt: 2))

        let again = RoomMembership.messageUpdate(room: r, xmppUsername: "app1_a", memberJid: "app1_a@xmpp.test", affiliation: "member")
        XCTAssertEqual(again, .none)
    }

    func testMessageLeaveRemovesAndDecrements() {
        let r = room(usersCnt: 2, members: [member("app1_a"), member("app1_b")])
        let left = RoomMembership.messageUpdate(room: r, xmppUsername: "app1_b", memberJid: "app1_b@xmpp.test", affiliation: "none")
        XCTAssertEqual(left, .set(members: [member("app1_a")], usersCnt: 1))
    }

    func testTruncatedRoomUnknownLeaverOnlyAdjustsCount() {
        let r = room(usersCnt: 40, members: [member("app1_a")])
        let update = RoomMembership.messageUpdate(room: r, xmppUsername: "app1_zzz", memberJid: "app1_zzz@xmpp.test", affiliation: "outcast")
        XCTAssertEqual(update, .countOnly(usersCnt: 39))
    }

    func testPresenceJoinNotCountedForTruncatedRoom() {
        let r = room(usersCnt: 40, members: [member("app1_a")])
        XCTAssertEqual(
            RoomMembership.presenceUpdate(room: r, nickname: "app1_new", affiliation: "member", isUnavailable: false),
            .none
        )
    }

    func testPresenceKickDecrementsAndNeverNegative() {
        let r = room(usersCnt: 1, members: [member("app1_a")])
        let kicked = RoomMembership.presenceUpdate(room: r, nickname: "app1_a", affiliation: "none", isUnavailable: true)
        XCTAssertEqual(kicked, .set(members: [], usersCnt: 0))
    }

    func testPresenceFromPlainOccupantIsIgnored() {
        let r = room(usersCnt: 1, members: [member("app1_a")])
        XCTAssertEqual(
            RoomMembership.presenceUpdate(room: r, nickname: "app1_b", affiliation: "none", isUnavailable: false),
            .none
        )
    }

    // MARK: - Member lookup route

    func testClassifyTable() {
        XCTAssertEqual(RoomMembersAPI.classify(status: 200, body: nil, isV1: true), .ok)
        XCTAssertEqual(RoomMembersAPI.classify(status: 404, body: "USER_NOT_FOUND", isV1: true), .notFound)
        XCTAssertEqual(RoomMembersAPI.classify(status: 404, body: "no route", isV1: true), .routeUnsupported)
        XCTAssertEqual(RoomMembersAPI.classify(status: 404, body: "no route", isV1: false), .notFound)
        XCTAssertEqual(RoomMembersAPI.classify(status: 403, body: nil, isV1: true), .forbidden)
        XCTAssertEqual(RoomMembersAPI.classify(status: 400, body: nil, isV1: true), .routeUnsupported)
        XCTAssertEqual(RoomMembersAPI.classify(status: 401, body: nil, isV1: false), .error)
        XCTAssertEqual(RoomMembersAPI.classify(status: 500, body: nil, isV1: true), .error)
    }

    func testRouteFallbackAndTTLRecovery() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var state = RoomMembersAPI.RouteState()
        XCTAssertEqual(state.route(for: .auto, now: t0), .v1)
        state.markV1Unsupported(now: t0)
        XCTAssertEqual(state.route(for: .auto, now: t0.addingTimeInterval(60)), .v2)
        XCTAssertEqual(state.route(for: .auto, now: t0.addingTimeInterval(RoomMembersAPI.routeTTL + 1)), .v1)
        // pinned modes ignore the learned state
        XCTAssertEqual(state.route(for: .v1, now: t0), .v1)
        XCTAssertEqual(state.route(for: .v2, now: t0), .v2)
    }

    func testParseUserShapes() {
        let wrapped = RoomMembersAPI.parseUser(json: json(#"{"result":{"_id":"u1","xmppUsername":"app1_u1","firstName":"Ann","lastName":"Lee"}}"#))
        XCTAssertEqual(wrapped?.firstName, "Ann")
        XCTAssertEqual(wrapped?.xmppUsername, "app1_u1")

        let array = RoomMembersAPI.parseUser(json: json(#"{"items":[],"data":[{"_id":"u2","firstName":"Bo"}]}"#))
        XCTAssertEqual(array?.id, "u2")

        let flat = RoomMembersAPI.parseUser(json: json(#"{"xmppUsername":"app1_u3","firstName":"Cy"}"#))
        XCTAssertEqual(flat?.xmppUsername, "app1_u3")

        XCTAssertNil(RoomMembersAPI.parseUser(json: json(#"{"unrelated":true}"#)))
    }

    // MARK: - Public chats directory

    func testPublicChatsMappingDropsReportedAndNamelessRows() throws {
        let rows = try JSONDecoder().decode([RoomsAPI.RawPublicChat].self, from: Data(#"""
        [
          {"name":"app1_r1","title":" Open ","description":"d","picture":"p","type":"public","e2ee":false,"reported":false},
          {"name":"app1_r2","title":"Hidden","reported":true},
          {"title":"No name"},
          {"name":"app1_r3","e2ee":true}
        ]
        """#.utf8))
        let mapped = RoomsAPI.mapPublicChats(rows)
        XCTAssertEqual(mapped.map(\.name), ["app1_r1", "app1_r3"])
        XCTAssertEqual(mapped.first?.title, "Open")
        XCTAssertEqual(mapped.last?.e2ee, true)
    }

    // MARK: - Private chat body

    func testPostPrivateRoomBodyOmitsE2eeUnlessTrue() throws {
        let plain = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(RoomsAPI.PostPrivateRoomBody(username: "u1", e2ee: nil))
        ) as? [String: Any]
        XCTAssertEqual(plain?["username"] as? String, "u1")
        XCTAssertNil(plain?["e2ee"], "e2ee must be absent for the default request")

        let encrypted = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(RoomsAPI.PostPrivateRoomBody(username: "u1", e2ee: true))
        ) as? [String: Any]
        XCTAssertEqual(encrypted?["e2ee"] as? Bool, true)
    }

    // MARK: - Invite stanza round trip

    func testInviteStanzaRoundTripsThroughParser() throws {
        let stanza = XMPPOperations.makeInviteStanza(
            to: "alice",
            roomJid: "chat_r1@conf.test",
            chatDomain: "@xmpp.test",
            nowMillis: 42
        )
        let parsed = try XCTUnwrap(XMPPStanzaParser.parse(stanza.toXML()))
        XCTAssertEqual(parsed.name, "message")
        XCTAssertEqual(parsed.attributes["to"], "chat_r1@conf.test")
        XCTAssertEqual(parsed.attributes["id"], "invite-rooms:42")
        let x = try XCTUnwrap(parsed.getChild("x"))
        XCTAssertEqual(x.attributes["xmlns"], "http://jabber.org/protocol/muc#user")
        XCTAssertEqual(x.getChild("invite")?.attributes["to"], "alice@xmpp.test")
    }
}
