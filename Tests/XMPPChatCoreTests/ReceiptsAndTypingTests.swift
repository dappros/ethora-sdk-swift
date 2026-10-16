//
//  ReceiptsAndTypingTests.swift
//  XMPPChatCoreTests
//
//  Wire shape and parser round-trips for XEP-0184 receipts, XEP-0333 read
//  markers and typing indicators, checked against ethora-chat-component
//  (sendReceivedReceipt, sendDisplayedMarker, sendTypingRequest, handleComposing).
//

import XCTest
@testable import XMPPChatCore

@MainActor
final class ReceiptsAndTypingTests: XCTestCase {

    private let room = "room1@conference.test"
    private let selfFrom = "me@xmpp.test/default"

    private func makeHandlers() -> StanzaHandlers {
        StanzaHandlers(client: nil)
    }

    private func textMessage(id: String = "m-1", body: String = "hello", sender: String = "bob") -> Message {
        Message(
            id: id,
            user: User(id: sender, xmppUsername: sender),
            date: Date(),
            body: body,
            roomJid: room
        )
    }

    // MARK: - Stanza shape

    func testReceivedReceiptStanzaMatchesWeb() {
        let stanza = XMPPReceiptStanzas.receivedReceipt(
            from: selfFrom, roomJID: room, messageId: "m-1", id: "message-received:1"
        )

        XCTAssertEqual(stanza.name, "message")
        XCTAssertEqual(stanza.attributes["type"], "groupchat")
        XCTAssertEqual(stanza.attributes["to"], room)
        XCTAssertEqual(stanza.attributes["id"], "message-received:1")

        let received = stanza.getChild("received")
        XCTAssertEqual(received?.attributes["xmlns"], "urn:xmpp:receipts")
        XCTAssertEqual(received?.attributes["id"], "m-1")
        XCTAssertEqual(received?.attributes["from"], selfFrom)
        XCTAssertEqual(stanza.getChild("store")?.attributes["xmlns"], "urn:xmpp:hints")
    }

    func testDisplayedMarkerStanzaMatchesWeb() {
        let stanza = XMPPReceiptStanzas.displayedMarker(
            from: selfFrom, roomJID: room, messageId: "m-7", id: "message-displayed:1"
        )

        XCTAssertEqual(stanza.attributes["id"], "message-displayed:1")
        XCTAssertEqual(stanza.attributes["type"], "groupchat")
        let displayed = stanza.getChild("displayed")
        XCTAssertEqual(displayed?.attributes["xmlns"], "urn:xmpp:chat-markers:0")
        XCTAssertEqual(displayed?.attributes["id"], "m-7")
        XCTAssertEqual(stanza.getChild("store")?.attributes["xmlns"], "urn:xmpp:hints")
    }

    func testTypingStanzaMatchesWeb() {
        let composing = XMPPChatStateStanzas.typing(chatId: room, fullName: "Me Myself", start: true, id: "typing-1")
        XCTAssertEqual(composing.attributes["type"], "groupchat")
        XCTAssertEqual(composing.attributes["to"], room)
        XCTAssertEqual(composing.getChild("composing")?.attributes["xmlns"], "http://jabber.org/protocol/chatstates")
        XCTAssertEqual(composing.getChild("data")?.attributes["fullName"], "Me Myself")
        XCTAssertTrue(XMPPChatStateStanzas.isChatState(composing))

        let paused = XMPPChatStateStanzas.typing(chatId: room, fullName: "Me Myself", start: false, id: "stop-typing-1")
        XCTAssertNotNil(paused.getChild("paused"))
        XCTAssertNil(paused.getChild("composing"))
    }

    // MARK: - Round trips through the parsers

    func testReceivedReceiptRoundTrip() {
        // The MUC rewrites the outer `from` to room/nick; the real sender
        // travels in <received from>.
        var stanza = XMPPReceiptStanzas.receivedReceipt(
            from: "bob@xmpp.test/default", roomJID: room, messageId: "m-42", id: "message-received:9"
        )
        stanza.attributes["from"] = "\(room)/bob"

        let handlers = makeHandlers()
        var got: (String, String, String, Int64)?
        handlers.onReceiptReceived = { room, messageId, user, ts in got = (room, messageId, user, ts) }
        handlers.handleReceivedReceipt(stanza)

        XCTAssertEqual(got?.0, room)
        XCTAssertEqual(got?.1, "m-42")
        XCTAssertEqual(got?.2, "bob")
        XCTAssertGreaterThan(got?.3 ?? 0, 0)
    }

    func testDisplayedMarkerRoundTrip() {
        var stanza = XMPPReceiptStanzas.displayedMarker(
            from: "carol@xmpp.test/default", roomJID: room, messageId: "m-9", id: "message-displayed:3"
        )
        stanza.attributes["from"] = "\(room)/carol"

        let handlers = makeHandlers()
        var got: (String, String, String)?
        handlers.onDisplayedMarkerReceived = { room, user, messageId in got = (room, user, messageId) }
        handlers.handleDisplayedMarker(stanza)

        XCTAssertEqual(got?.0, room)
        XCTAssertEqual(got?.1, "carol")
        XCTAssertEqual(got?.2, "m-9")
    }

    func testReceiptWithoutReceivedChildIsIgnored() {
        let stanza = XMPPStanza(name: "message", attributes: ["id": "message-received:1", "from": "\(room)/bob"])
        let handlers = makeHandlers()
        var called = false
        handlers.onReceiptReceived = { _, _, _, _ in called = true }
        handlers.handleReceivedReceipt(stanza)
        XCTAssertFalse(called)
    }

    func testReceiptsAndChatStatesDoNotSurfaceAsMessages() {
        let handlers = makeHandlers()
        var surfaced: [Message] = []
        handlers.onMessageReceived = { message, _ in surfaced.append(message) }

        let receipt = XMPPReceiptStanzas.receivedReceipt(
            from: "bob@xmpp.test/default", roomJID: room, messageId: "m-1", id: "message-received:1"
        )
        handlers.onRealtimeMessage(receipt)

        var typingStanza = XMPPChatStateStanzas.typing(chatId: room, fullName: "Bob B", start: true, id: "typing-1")
        typingStanza.attributes["from"] = "\(room)/bob"
        handlers.onRealtimeMessage(typingStanza)

        XCTAssertTrue(surfaced.isEmpty)
    }

    // MARK: - Composing parser

    func testComposingCarriesFullNameFromData() {
        let stanza = XMPPStanza(
            name: "message",
            attributes: ["from": "\(room)/bob", "type": "groupchat"],
            children: [
                XMPPStanza(name: "composing", attributes: ["xmlns": "http://jabber.org/protocol/chatstates"]),
                XMPPStanza(name: "data", attributes: ["fullName": "Bob Stone"]),
            ]
        )
        let handlers = makeHandlers()
        var calls: [(String, String, String, Bool)] = []
        handlers.onComposingChanged = { r, n, f, c in calls.append((r, n, f, c)) }
        handlers.handleComposing(stanza, currentUser: "me")

        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.0, room)
        XCTAssertEqual(calls.first?.1, "bob")
        XCTAssertEqual(calls.first?.2, "Bob Stone")
        XCTAssertEqual(calls.first?.3, true)
    }

    func testPausedReportsStopAndOwnEchoIsFiltered() {
        let paused = XMPPStanza(
            name: "message",
            attributes: ["from": "\(room)/bob"],
            children: [XMPPStanza(name: "paused", attributes: ["xmlns": "http://jabber.org/protocol/chatstates"])]
        )
        let ownEcho = XMPPStanza(
            name: "message",
            attributes: ["from": "\(room)/Me_Myself"],
            children: [
                XMPPStanza(name: "composing"),
                XMPPStanza(name: "data", attributes: ["fullName": "Me Myself"]),
            ]
        )
        let handlers = makeHandlers()
        var calls: [(String, Bool)] = []
        handlers.onComposingChanged = { _, n, _, c in calls.append((n, c)) }

        handlers.handleComposing(paused, currentUser: "me")
        handlers.handleComposing(ownEcho, currentUser: "me_myself")

        XCTAssertEqual(calls.count, 1, "own echo must be dropped")
        XCTAssertEqual(calls.first?.0, "bob")
        XCTAssertEqual(calls.first?.1, false)
    }

    // MARK: - ComposingTracker

    func testTrackerKeepsEveryTyperAndRemovesOnPaused() {
        let tracker = ComposingTracker()
        var published: [[String]] = []
        tracker.onChange = { _, typers, _ in published.append(typers) }
        let t0 = Date(timeIntervalSince1970: 1_000)

        tracker.apply(roomJID: room, nickname: "bob", fullName: "Bob", isComposing: true, now: t0)
        tracker.apply(roomJID: room, nickname: "carol", fullName: "Carol", isComposing: true, now: t0)
        XCTAssertEqual(tracker.names(roomJID: room, now: t0), ["Bob", "Carol"])
        XCTAssertEqual(published.last, ["Bob", "Carol"])

        tracker.apply(roomJID: room, nickname: "bob", fullName: "Bob", isComposing: false, now: t0)
        XCTAssertEqual(published.last, ["Carol"], "a paused from one user must not clear the others")
    }

    func testTrackerExpiresTyperWhosePausedWasLost() {
        let tracker = ComposingTracker()
        var lastChange: (typers: [String], composing: Bool)?
        tracker.onChange = { _, typers, composing in lastChange = (typers, composing) }
        let t0 = Date(timeIntervalSince1970: 2_000)

        tracker.apply(roomJID: room, nickname: "bob", fullName: "Bob", isComposing: true, now: t0)
        XCTAssertEqual(lastChange?.typers, ["Bob"])

        let later = t0.addingTimeInterval(ComposingTracker.expirySeconds + 1)
        tracker.pruneExpired(roomJID: room, now: later)

        XCTAssertEqual(lastChange?.typers, [])
        XCTAssertEqual(lastChange?.composing, false)
    }

    func testTrackerRefreshExtendsExpiry() {
        let tracker = ComposingTracker()
        var publishes = 0
        tracker.onChange = { _, _, _ in publishes += 1 }
        let t0 = Date(timeIntervalSince1970: 3_000)

        tracker.apply(roomJID: room, nickname: "bob", fullName: "Bob", isComposing: true, now: t0)
        tracker.apply(roomJID: room, nickname: "bob", fullName: "Bob", isComposing: true, now: t0.addingTimeInterval(20))

        let check = t0.addingTimeInterval(40)
        XCTAssertEqual(tracker.names(roomJID: room, now: check), ["Bob"], "a fresh composing renews the entry")
        let before = publishes
        tracker.pruneExpired(roomJID: room, now: check)
        XCTAssertEqual(publishes, before, "nothing changed, nothing published")
    }

    // MARK: - Acknowledgement policy

    func testAcknowledgesOthersTextAndMediaOnly() {
        XCTAssertTrue(ReceiptPolicy.shouldAcknowledge(textMessage(), selfUsername: "me"))

        XCTAssertFalse(ReceiptPolicy.shouldAcknowledge(textMessage(sender: "me"), selfUsername: "me"),
                       "never ack our own echo")

        var system = textMessage()
        system.isSystemMessage = "true"
        XCTAssertFalse(ReceiptPolicy.shouldAcknowledge(system, selfUsername: "me"))

        XCTAssertFalse(ReceiptPolicy.shouldAcknowledge(textMessage(body: "   "), selfUsername: "me"),
                       "empty body is not a visible message")

        var media = textMessage(body: "media")
        media.isMediafile = "true"
        XCTAssertTrue(ReceiptPolicy.shouldAcknowledge(media, selfUsername: "me"))
    }

    func testHistoryLedgerDedupesAndEvictsOldest() {
        var ledger = HistoryReceiptLedger(capacity: 2)
        XCTAssertTrue(ledger.insert(roomJID: room, messageId: "a"))
        XCTAssertFalse(ledger.insert(roomJID: room, messageId: "a"))
        XCTAssertTrue(ledger.insert(roomJID: room, messageId: "b"))
        XCTAssertTrue(ledger.insert(roomJID: room, messageId: "c"))
        XCTAssertTrue(ledger.insert(roomJID: room, messageId: "a"), "oldest entry was evicted at capacity")
        XCTAssertTrue(ledger.insert(roomJID: "other@conference.test", messageId: "a"), "keys are per room")
    }

    // MARK: - Stored fields

    func testReceivedByAndWatermarkSurviveCodableAndOldJSONStillDecodes() throws {
        var message = textMessage()
        message.receivedBy = ["bob": 1_700_000_000_000]
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        XCTAssertEqual(decoded.receivedBy, ["bob": 1_700_000_000_000])

        let legacy = #"{"id":"m-1","user":{"id":"bob","xmppUsername":"bob"},"date":0,"body":"hi","roomJid":"room1@conference.test"}"#
        let legacyDecoded = try JSONDecoder().decode(Message.self, from: Data(legacy.utf8))
        XCTAssertNil(legacyDecoded.receivedBy)
    }

    func testRoomWatermarkDefaultsToNil() {
        var room = Room(id: "r", jid: self.room, name: "r", title: "r")
        XCTAssertNil(room.lastDisplayedByUser)
        room.lastDisplayedByUser = ["bob": "m-3"]
        XCTAssertEqual(room.lastDisplayedByUser?["bob"], "m-3")
    }
}
