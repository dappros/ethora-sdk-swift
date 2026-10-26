//
//  P2PCallTests.swift
//  XMPPChatCoreTests
//
//  Pure modules of the peer to peer call path: signal codec, negotiator, ICE
//  restart policy, call-token attribute parsing and the busy/glare decision.
//

import XCTest
@testable import XMPPChatCore

final class P2PCallTests: XCTestCase {
    // MARK: - Helpers

    private func sdpSignal(_ name: P2PSignalName, _ sdp: String, callId: String = "c1", from: String = "bob") -> P2PSignal {
        P2PSignal(callId: callId, name: name, payload: .sdp(type: name.rawValue, sdp: sdp), fromLocal: from)
    }

    private func candidateSignal(_ text: String, callId: String = "c1", from: String = "bob") -> P2PSignal {
        P2PSignal(
            callId: callId,
            name: .candidate,
            payload: .candidate(P2PCandidatePayload(candidate: text, sdpMid: "0", sdpMLineIndex: 0)),
            fromLocal: from
        )
    }

    private func endSignal(callId: String = "c1", from: String = "bob") -> P2PSignal {
        P2PSignal(callId: callId, name: .end, payload: .end(reason: "hangup"), fromLocal: from)
    }

    // MARK: - Signal codec

    func testBuildAndParseRoundTrip() throws {
        let stanza = P2PSignalCodec.buildStanza(
            to: "bob@xmpp.test",
            callId: "c1",
            name: .offer,
            payload: .sdp(type: "offer", sdp: "v=0\r\no=- 1 2 IN IP4 0.0.0.0\r\n"),
            messageId: "m1"
        )
        XCTAssertEqual(stanza.attributes["type"], "chat")
        var received = stanza
        received.attributes["from"] = "Bob@xmpp.test/ios"
        let signal = try XCTUnwrap(P2PSignalCodec.parse(received))
        XCTAssertEqual(signal.callId, "c1")
        XCTAssertEqual(signal.name, .offer)
        XCTAssertEqual(signal.fromLocal, "bob")
        XCTAssertEqual(signal.payload, .sdp(type: "offer", sdp: "v=0\r\no=- 1 2 IN IP4 0.0.0.0\r\n"))
    }

    func testParseRejectsMalformedSignals() {
        func message(_ attrs: [String: String]) -> XMPPStanza {
            XMPPStanza(name: "message", attributes: ["from": "bob@x"], children: [
                XMPPStanza(name: "data", attributes: attrs),
            ])
        }
        XCTAssertNil(P2PSignalCodec.parse(message(["type": "call-p2p", "callId": "c1", "signal": "nope", "payload": "{}"])))
        XCTAssertNil(P2PSignalCodec.parse(message(["type": "call-p2p", "signal": "end", "payload": "{}"])))
        XCTAssertNil(P2PSignalCodec.parse(message(["type": "call-p2p", "callId": "c1", "signal": "end", "payload": "not json"])))
        XCTAssertNil(P2PSignalCodec.parse(message(["type": "call-p2p", "callId": "c1", "signal": "offer", "payload": "{\"type\":\"answer\",\"sdp\":\"x\"}"])))
        XCTAssertNil(P2PSignalCodec.parse(message(["type": "call-state", "callId": "c1", "signal": "end", "payload": "{}"])))
    }

    func testFreshness() {
        let stale = P2PSignal(callId: "c", name: .offer, payload: .sdp(type: "offer", sdp: "x"), ageMs: 60_000)
        let live = P2PSignal(callId: "c", name: .offer, payload: .sdp(type: "offer", sdp: "x"), ageMs: 500)
        let delayedEnd = P2PSignal(callId: "c", name: .end, payload: .end(reason: nil), delayed: true)
        let lateEnd = P2PSignal(callId: "c", name: .end, payload: .end(reason: nil), ageMs: 60_000)
        XCTAssertFalse(P2PSignalCodec.isFresh(stale))
        XCTAssertTrue(P2PSignalCodec.isFresh(live))
        XCTAssertFalse(P2PSignalCodec.isFresh(delayedEnd))
        XCTAssertTrue(P2PSignalCodec.isFresh(lateEnd))
    }

    // MARK: - Negotiator

    func testCalleeHoldsOfferUntilReadyAndFlushesCandidates() {
        let n = P2PNegotiator(callId: "c1", role: .callee, peerLocal: "bob")
        XCTAssertEqual(n.receive(sdpSignal(.offer, "O1")), [])
        XCTAssertEqual(n.receive(candidateSignal("cand1")), [])
        XCTAssertEqual(n.markReady(), [.applyOffer(sdp: "O1", initial: true, rollback: false)])
        XCTAssertEqual(
            n.markRemoteApplied(),
            [.addCandidate(P2PCandidatePayload(candidate: "cand1", sdpMid: "0", sdpMLineIndex: 0))]
        )
        // Later candidates apply at once, duplicates are ignored.
        XCTAssertEqual(n.receive(candidateSignal("cand2")).count, 1)
        XCTAssertEqual(n.receive(candidateSignal("cand2")), [])
    }

    func testSignalsFromOthersOrOtherCallsAreIgnored() {
        let n = P2PNegotiator(callId: "c1", role: .callee, peerLocal: "bob@xmpp.test")
        _ = n.markReady()
        XCTAssertEqual(n.receive(sdpSignal(.offer, "O1", from: "mallory")), [])
        XCTAssertEqual(n.receive(sdpSignal(.offer, "O1", callId: "other")), [])
        XCTAssertEqual(n.receive(sdpSignal(.offer, "O1")).count, 1)
        // A repeated identical offer is a no-op.
        XCTAssertEqual(n.receive(sdpSignal(.offer, "O1")), [])
    }

    func testCallerAcceptsAnswerOnlyAfterLocalOffer() {
        let n = P2PNegotiator(callId: "c1", role: .caller, peerLocal: "bob")
        _ = n.markReady()
        XCTAssertEqual(n.receive(sdpSignal(.answer, "A1")), [])
        n.markLocalOffer()
        XCTAssertTrue(n.awaitingAnswer)
        XCTAssertEqual(n.receive(sdpSignal(.answer, "A1")), [.applyAnswer(sdp: "A1")])
        XCTAssertFalse(n.awaitingAnswer)
        XCTAssertEqual(n.receive(sdpSignal(.answer, "A1")), [])
    }

    func testCallerNeverTakesAnInitialOffer() {
        let n = P2PNegotiator(callId: "c1", role: .caller, peerLocal: "bob")
        _ = n.markReady()
        XCTAssertEqual(n.receive(sdpSignal(.offer, "O1")), [])
    }

    func testGlareCallerKeepsOwnOfferCalleeYields() {
        let caller = P2PNegotiator(callId: "c1", role: .caller, peerLocal: "bob")
        _ = caller.markReady()
        caller.markLocalOffer()
        _ = caller.markRemoteApplied()
        XCTAssertEqual(caller.receive(sdpSignal(.offer, "R1")), [])

        let callee = P2PNegotiator(callId: "c1", role: .callee, peerLocal: "bob")
        _ = callee.markReady()
        _ = callee.receive(sdpSignal(.offer, "O1"))
        _ = callee.markRemoteApplied()
        callee.markLocalOffer()
        XCTAssertEqual(
            callee.receive(sdpSignal(.offer, "R1")),
            [.applyOffer(sdp: "R1", initial: false, rollback: true)]
        )
    }

    func testRemoteEndStopsTheNegotiation() {
        let n = P2PNegotiator(callId: "c1", role: .callee, peerLocal: "bob")
        XCTAssertEqual(n.receive(endSignal()), [.remoteEnd(reason: "hangup")])
        XCTAssertTrue(n.isEnded)
        XCTAssertEqual(n.receive(sdpSignal(.offer, "O1")), [])
    }

    // MARK: - ICE restart policy

    func testDisconnectedWaitsThenRestartsOnce() {
        var policy = IceRestartPolicy(graceMs: 100, restartDeadlineMs: 500, maxRestartsPerCall: 3)
        XCTAssertEqual(policy.onState(.disconnected), .wait(ms: 100))
        XCTAssertEqual(policy.onGraceElapsed(), .restart(deadlineMs: 500))
        // A second grace expiry in the same outage gives up instead of looping.
        XCTAssertEqual(policy.onGraceElapsed(), .giveUp(reason: "restart-did-not-recover"))
    }

    func testFailedRestartsImmediatelyAndRecoveryResetsTheOutage() {
        var policy = IceRestartPolicy()
        XCTAssertEqual(policy.onState(.failed), .restart(deadlineMs: 15_000))
        XCTAssertEqual(policy.onState(.connected), .recovered)
        XCTAssertEqual(policy.onState(.failed), .restart(deadlineMs: 15_000))
        XCTAssertEqual(policy.restartCount, 2)
    }

    func testRestartCapPerCall() {
        var policy = IceRestartPolicy(maxRestartsPerCall: 1)
        XCTAssertEqual(policy.onState(.failed), .restart(deadlineMs: 15_000))
        _ = policy.onState(.connected)
        XCTAssertEqual(policy.onState(.failed), .giveUp(reason: "too-many-restarts"))
    }

    func testRestartDeadline() {
        let policy = IceRestartPolicy()
        XCTAssertEqual(policy.onRestartDeadline(stillDown: true), .giveUp(reason: "restart-timeout"))
        XCTAssertEqual(policy.onRestartDeadline(stillDown: false), .none)
    }

    // MARK: - Call-token attributes

    func testLegacyTokenWithoutModeIsLiveKit() {
        let attrs = CallModeParsing.parseCallTokenAttrs(["token": " t ", "room": "r", "callId": "c1"])
        XCTAssertEqual(attrs.mode, .livekit)
        XCTAssertFalse(attrs.group)
        XCTAssertEqual(attrs.token, "t")
        XCTAssertNil(attrs.livekitUrl)
    }

    func testP2PTokenParsesIceAndForcesNonGroup() throws {
        let ice = #"[{"urls":["turn:t.example:3478"],"username":"u","credential":"p"},{"urls":"bogus:x"}]"#
        let attrs = CallModeParsing.parseCallTokenAttrs([
            "mode": "p2p", "room": "r", "callId": "c1", "group": "true", "ice": ice,
            "callerName": "Alice\u{202E}", "caller": "alice",
        ])
        XCTAssertEqual(attrs.mode, .p2p)
        XCTAssertFalse(attrs.group)
        XCTAssertEqual(attrs.iceServers, [IceServerConfig(urls: ["turn:t.example:3478"], username: "u", credential: "p")])
        XCTAssertEqual(attrs.callerName, "Alice")
        XCTAssertEqual(attrs.caller, "alice")
    }

    func testLivekitUrlMustBeAWebUrl() {
        XCTAssertEqual(CallModeParsing.normalizeLivekitUrl("wss://lk.example.com"), "wss://lk.example.com")
        XCTAssertNil(CallModeParsing.normalizeLivekitUrl("javascript:alert(1)"))
        XCTAssertNil(CallModeParsing.normalizeLivekitUrl(""))
    }

    func testSystemAccountTrust() {
        let appId = String(repeating: "a1", count: 12)
        XCTAssertTrue(CallModeParsing.isSystemAccountSender("\(appId)_\(appId)@xmpp.test/res", expectedDomain: "xmpp.test"))
        XCTAssertFalse(CallModeParsing.isSystemAccountSender("\(appId)_\(appId)@evil.test", expectedDomain: "xmpp.test"))
        XCTAssertFalse(CallModeParsing.isSystemAccountSender("\(appId)_\(String(repeating: "b2", count: 12))@xmpp.test"))
        XCTAssertFalse(CallModeParsing.isSystemAccountSender(nil))
    }

    func testRawRoomNamesAreNotCallerNames() {
        let id = String(repeating: "ab", count: 12)
        XCTAssertEqual(CallModeParsing.sanitizeCallName("\(id)_\(id)-\(id)_\(id)"), "")
        XCTAssertEqual(CallModeParsing.sanitizeCallName("  Alice   B  "), "Alice B")
    }

    func testCreateResponseParsing() throws {
        let p2p = try CallModeParsing.parseCallCreateResponse(
            ["mode": "p2p", "callId": "c9", "kind": "audio", "iceServers": [["urls": "stun:s.example:3478"]]],
            fallbackKind: .video
        )
        XCTAssertEqual(p2p.mode, .p2p)
        XCTAssertEqual(p2p.kind, .audio)
        XCTAssertEqual(p2p.iceServers.count, 1)
        // An old server answers with no mode.
        let legacy = try CallModeParsing.parseCallCreateResponse(["ok": true], fallbackKind: .video)
        XCTAssertEqual(legacy.mode, .livekit)
        XCTAssertThrowsError(try CallModeParsing.parseCallCreateResponse(["mode": "p2p"], fallbackKind: .video))
    }

    // MARK: - Busy / glare

    func testIncomingWhileBusyDecisions() {
        func snap(_ phase: CallPhase, _ direction: CallDirection?, _ mode: CallMode, _ id: String?) -> CallModeDecision.Snapshot {
            .init(phase: phase, direction: direction, mode: mode, callId: id, roomBareName: "room")
        }
        func decide(_ s: CallModeDecision.Snapshot, _ mode: CallMode, _ id: String?) -> CallModeDecision {
            CallModeDecision.incomingWhileBusy(current: s, incomingMode: mode, incomingCallId: id, incomingRoomBareName: "room")
        }
        XCTAssertEqual(decide(snap(.idle, nil, .livekit, nil), .p2p, "b"), .accept)
        XCTAssertEqual(decide(snap(.ringingIncoming, .incoming, .p2p, "a"), .p2p, "a"), .duplicate)
        XCTAssertEqual(decide(snap(.connecting, .incoming, .livekit, "a"), .livekit, "b"), .replace)
        XCTAssertEqual(decide(snap(.inCall, .incoming, .p2p, "a"), .p2p, "b"), .busy)
        XCTAssertEqual(decide(snap(.requesting, .outgoing, .p2p, "b"), .p2p, "a"), .glareYield)
        XCTAssertEqual(decide(snap(.requesting, .outgoing, .p2p, "a"), .p2p, "b"), .glareKeep)
    }

    // MARK: - Inbox

    func testInboxBuffersUntilAttachThenDelivers() {
        let inbox = P2PSignalInbox()
        XCTAssertEqual(inbox.receive(sdpSignal(.offer, "O1")), .buffered)
        var got: [P2PSignalName] = []
        let detach = inbox.attach(callId: "c1") { got.append($0.name) }
        XCTAssertEqual(got, [.offer])
        XCTAssertEqual(inbox.receive(candidateSignal("x")), .delivered)
        detach()
        // After the call closed, stragglers are dropped, not buffered.
        XCTAssertEqual(inbox.receive(candidateSignal("y")), .dropped)
    }
}
