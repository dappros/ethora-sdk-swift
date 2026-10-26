//
//  CallStoreTests.swift
//  XMPPChatCoreTests
//
//  State-machine tests for CallStore (web callSlice reducers and the incoming
//  handler) and for the call-log merge in RoomStore.
//

import XCTest
@testable import XMPPChatCore

@MainActor
final class CallStoreTests: XCTestCase {

    override func setUp() async throws {
        ConfigStore.shared.reset()
        RoomStore.shared.clearAll()
    }

    override func tearDown() async throws {
        ConfigStore.shared.reset()
        RoomStore.shared.clearAll()
    }

    // MARK: - Helpers

    private func enableCalls() {
        var patch = ChatConfig()
        patch.videoCalls = VideoCallsConfig(enabled: true, livekitUrl: "wss://lk.test")
        ConfigStore.shared.mergeConfig(patch)
    }

    private func makeRoom(jid: String, name: String, type: String = "private", usersCnt: Int = 2) -> Room {
        var room = Room(
            id: jid,
            jid: jid,
            name: name,
            title: name,
            lastViewedTimestamp: nil,
            unreadMessages: 0
        )
        room.type = RoomType(rawValue: type)
        room.usersCnt = usersCnt
        return room
    }

    private func makeToken(room: String, kind: CallKind = .video, callId: String? = nil) -> IncomingCallToken {
        IncomingCallToken(
            token: "t.oken.sig",
            room: room,
            stanzaKind: kind,
            callId: callId,
            callerName: "Alice",
            jwtCallId: nil
        )
    }

    // MARK: - Outgoing lifecycle

    func testOutgoingCallLifecycleFromRequestToConnected() {
        let store = CallStore(outgoingCallTimeout: 60)
        store.startOutgoingCall(
            roomJid: "room1@conference.test",
            roomName: "Bob",
            roomBareName: "room1",
            kind: .video,
            peerXmppUsername: "bob"
        )
        XCTAssertEqual(store.state.phase, .requesting)
        XCTAssertEqual(store.state.direction, .outgoing)
        XCTAssertTrue(store.isBusy)

        store.setOutgoingCallToken(roomJid: "room1@conference.test", token: "tok", callId: "c-1")
        XCTAssertEqual(store.state.phase, .connecting)
        XCTAssertEqual(store.state.callId, "c-1")
        XCTAssertEqual(store.state.token, "tok")

        store.markConnected()
        XCTAssertEqual(store.state.phase, .inCall)
        XCTAssertNotNil(store.state.connectedAt)

        store.resetCall()
        XCTAssertEqual(store.state.phase, .idle)
        XCTAssertFalse(store.isBusy)
    }

    func testOutgoingTokenForAnotherRoomIsIgnored() {
        let store = CallStore(outgoingCallTimeout: 60)
        store.startOutgoingCall(roomJid: "room1@conference.test", roomName: nil, roomBareName: nil, kind: .video, peerXmppUsername: nil)
        store.setOutgoingCallToken(roomJid: "other@conference.test", token: "tok", callId: nil)
        XCTAssertEqual(store.state.phase, .requesting)
        XCTAssertNil(store.state.token)
    }

    func testUnansweredOutgoingCallTimesOut() async throws {
        let store = CallStore(outgoingCallTimeout: 0.05)
        store.startOutgoingCall(roomJid: "room1@conference.test", roomName: nil, roomBareName: nil, kind: .audio, peerXmppUsername: nil)

        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(store.state.phase, .error)
        XCTAssertEqual(store.state.error, "No answer - call timed out")
    }

    func testTimeoutDoesNotFireOnceTheCallIsConnecting() async throws {
        let store = CallStore(outgoingCallTimeout: 0.05)
        store.startOutgoingCall(roomJid: "room1@conference.test", roomName: nil, roomBareName: nil, kind: .video, peerXmppUsername: nil)
        store.setOutgoingCallToken(roomJid: "room1@conference.test", token: "tok", callId: nil)

        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(store.state.phase, .connecting)
    }

    // MARK: - Incoming

    func testIncomingTokenIsIgnoredWhileVideoCallsAreDisabled() {
        RoomStore.shared.addRoom(makeRoom(jid: "room1@conference.test", name: "Bob"))
        let store = CallStore(outgoingCallTimeout: 60)

        store.apply(.token(makeToken(room: "room1")), selfXmppUsername: "alice")
        XCTAssertEqual(store.state.phase, .idle)
    }

    func testIncomingTokenRingsInAOneToOneRoomWhenEnabled() {
        enableCalls()
        RoomStore.shared.addRoom(makeRoom(jid: "room1@conference.test", name: "Bob"))
        let store = CallStore(outgoingCallTimeout: 60)

        store.apply(.token(makeToken(room: "room1", callId: "c-9")), selfXmppUsername: "alice")
        XCTAssertEqual(store.state.phase, .ringingIncoming)
        XCTAssertEqual(store.state.direction, .incoming)
        XCTAssertEqual(store.state.roomJid, "room1@conference.test")
        XCTAssertEqual(store.state.callId, "c-9")
        // The caller's own name (from the token) wins over the room title.
        XCTAssertEqual(store.state.roomName, "Alice")
    }

    func testIncomingP2PTokenRingsWithoutALiveKitToken() {
        enableCalls()
        RoomStore.shared.addRoom(makeRoom(jid: "room1@conference.test", name: "Bob"))
        let store = CallStore(outgoingCallTimeout: 60)
        let token = IncomingCallToken(
            token: "", room: "room1", stanzaKind: .audio, callId: "c-p2p",
            callerName: "", jwtCallId: nil, mode: .p2p, attrCallerName: "Alice"
        )

        store.apply(.token(token), selfXmppUsername: "alice")
        XCTAssertEqual(store.state.phase, .ringingIncoming)
        XCTAssertEqual(store.state.mode, .p2p)
        XCTAssertEqual(store.state.callId, "c-p2p")
        XCTAssertEqual(store.state.token, "")
        XCTAssertEqual(store.state.roomName, "Alice")
    }

    func testGroupTokenRingsInAGroupRoomWithTheRoomAsTheName() {
        enableCalls()
        RoomStore.shared.addRoom(makeRoom(jid: "group7@conference.test", name: "Team", type: "group", usersCnt: 9))
        let store = CallStore(outgoingCallTimeout: 60)
        let token = IncomingCallToken(
            token: "t.oken.sig", room: "group7", stanzaKind: .video, callId: "c-g",
            callerName: "", jwtCallId: nil, group: true, attrCallerName: "Alice"
        )

        store.apply(.token(token), selfXmppUsername: "bob")
        XCTAssertEqual(store.state.phase, .ringingIncoming)
        XCTAssertTrue(store.state.isGroup)
        XCTAssertEqual(store.state.roomName, "Team")
        XCTAssertEqual(store.state.callerName, "Alice")
        XCTAssertNil(store.state.peerXmppUsername)
    }

    func testGroupTokenIsIgnoredWhenGroupCallsAreNotAllowed() {
        var patch = ChatConfig()
        patch.videoCalls = VideoCallsConfig(enabled: true, livekitUrl: "wss://lk.test", allowedRoomTypes: ["private"])
        ConfigStore.shared.mergeConfig(patch)
        RoomStore.shared.addRoom(makeRoom(jid: "group8@conference.test", name: "Team", type: "group", usersCnt: 9))
        let store = CallStore(outgoingCallTimeout: 60)
        let token = IncomingCallToken(
            token: "t.oken.sig", room: "group8", stanzaKind: .video, callId: "c-g2",
            callerName: "", jwtCallId: nil, group: true
        )
        store.apply(.token(token), selfXmppUsername: "bob")
        XCTAssertEqual(store.state.phase, .idle)
        enableCalls()
    }

    func testOneGroupMemberDecliningDoesNotEndTheCall() {
        enableCalls()
        RoomStore.shared.addRoom(makeRoom(jid: "group9@conference.test", name: "Team", type: "group", usersCnt: 9))
        let store = CallStore(outgoingCallTimeout: 60)
        let token = IncomingCallToken(
            token: "t.oken.sig", room: "group9", stanzaKind: .video, callId: "c-g3",
            callerName: "", jwtCallId: nil, group: true
        )
        store.apply(.token(token), selfXmppUsername: "bob")
        store.apply(.state(state: "declined", callId: "c-g3", room: "group9", callLog: nil), selfXmppUsername: "bob")
        XCTAssertEqual(store.state.phase, .ringingIncoming)
        store.apply(.state(state: "ended", callId: "c-g3", room: "group9", callLog: nil), selfXmppUsername: "bob")
        XCTAssertEqual(store.state.phase, .idle)
    }

    func testIncomingTokenInAGroupRoomIsIgnored() {
        enableCalls()
        RoomStore.shared.addRoom(makeRoom(jid: "group1@conference.test", name: "Team", type: "group", usersCnt: 9))
        let store = CallStore(outgoingCallTimeout: 60)

        store.apply(.token(makeToken(room: "group1")), selfXmppUsername: "alice")
        XCTAssertEqual(store.state.phase, .idle)
    }

    func testCallInviteHintOverridesStanzaKindWhenTokenArrives() {
        enableCalls()
        RoomStore.shared.addRoom(makeRoom(jid: "room1@conference.test", name: "Bob"))
        let store = CallStore(outgoingCallTimeout: 60)

        store.apply(.invite(room: "room1", callId: nil, kind: .audio), selfXmppUsername: "alice")
        store.apply(.token(makeToken(room: "room1", kind: .video)), selfXmppUsername: "alice")
        XCTAssertEqual(store.state.kind, .audio)
    }

    func testIncomingTokenDoesNotReplaceAnActiveCall() {
        enableCalls()
        RoomStore.shared.addRoom(makeRoom(jid: "room1@conference.test", name: "Bob"))
        let store = CallStore(outgoingCallTimeout: 60)
        store.setIncomingCallToken(
            roomJid: "room1@conference.test", roomName: "Bob", roomBareName: "room1",
            token: "first", kind: .video, callId: "c-1", peerXmppUsername: "bob"
        )
        store.markConnected()

        store.apply(.token(makeToken(room: "room1")), selfXmppUsername: "alice")
        XCTAssertEqual(store.state.token, "first")
        XCTAssertEqual(store.state.phase, .inCall)
    }

    func testTerminalCallStateForTheCallEndsIt() {
        enableCalls()
        RoomStore.shared.addRoom(makeRoom(jid: "room1@conference.test", name: "Bob"))
        let store = CallStore(outgoingCallTimeout: 60)
        store.apply(.token(makeToken(room: "room1", callId: "c-9")), selfXmppUsername: "alice")

        store.apply(.state(state: "cancelled", callId: "c-9", room: "room1", callLog: nil), selfXmppUsername: "alice")
        XCTAssertEqual(store.state.phase, .idle)
    }

    func testTerminalCallStateForAnotherCallIsIgnored() {
        enableCalls()
        RoomStore.shared.addRoom(makeRoom(jid: "room1@conference.test", name: "Bob"))
        let store = CallStore(outgoingCallTimeout: 60)
        store.apply(.token(makeToken(room: "room1", callId: "c-9")), selfXmppUsername: "alice")

        store.apply(.state(state: "ended", callId: "c-other", room: "elsewhere", callLog: nil), selfXmppUsername: "alice")
        XCTAssertEqual(store.state.phase, .ringingIncoming)
    }

    func testServerCallLogEndsTheActiveCall() {
        enableCalls()
        RoomStore.shared.addRoom(makeRoom(jid: "room1@conference.test", name: "Bob"))
        let store = CallStore(outgoingCallTimeout: 60)
        store.apply(.token(makeToken(room: "room1", callId: "c-9")), selfXmppUsername: "alice")

        let meta = CallLogMeta(callId: "c-9", durationMs: 4_000, kind: .video, callerXmppUsername: "bob")
        store.apply(.state(state: "", callId: "c-9", room: "room1", callLog: meta), selfXmppUsername: "alice")
        XCTAssertEqual(store.state.phase, .idle)
    }

    // MARK: - RoomStore call-log merge

    func testRoomStoreKeepsOneCallLogRowPerCallIdWithTheLongerDuration() {
        RoomStore.shared.addRoom(makeRoom(jid: "room1@conference.test", name: "Bob"))

        func logRow(id: String, durationMs: Int64) -> Message {
            var message = Message(
                id: id,
                user: User(id: "u1"),
                date: Date(),
                body: "Call",
                roomJid: "room1@conference.test",
                timestamp: 1_000
            )
            message.callLog = CallLogMeta(callId: "c-5", durationMs: durationMs, kind: .video, callerXmppUsername: "alice")
            return message
        }

        RoomStore.shared.addMessage(logRow(id: "calllog-c-5", durationMs: 0), toRoomJID: "room1@conference.test")
        RoomStore.shared.addMessage(logRow(id: "server-1", durationMs: 12_000), toRoomJID: "room1@conference.test")
        RoomStore.shared.addMessage(logRow(id: "server-2", durationMs: 3_000), toRoomJID: "room1@conference.test")

        let rows = RoomStore.shared.rooms["room1@conference.test"]?.messages.filter { $0.callLog != nil } ?? []
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.callLog?.durationMs, 12_000)
    }
}
