//
//  ReceiptStateTests.swift
//  XMPPChatUITests
//
//  Tick rules for our outgoing messages, mirroring web MessageBubble tickInfo:
//  seen beats delivered beats sent; pending and failed show no tick.
//

import XCTest
@testable import XMPPChatUI
@testable import XMPPChatCore

final class ReceiptStateTests: XCTestCase {

    private let me = "me"

    private func message(_ id: String, mine: Bool = true) -> Message {
        Message(
            id: id,
            user: User(id: mine ? me : "bob", xmppUsername: mine ? me : "bob"),
            date: Date(),
            body: "text \(id)",
            roomJid: "room1@conference.test"
        )
    }

    func testPlainOwnMessageIsSent() {
        let messages = [message("m-1")]
        XCTAssertEqual(ReceiptState.resolve(for: messages[0], in: messages, watermarks: [:], selfUsername: me), .sent)
    }

    func testPendingAndFailedShowNoTick() {
        var pending = message("m-1")
        pending.pending = true
        XCTAssertEqual(ReceiptState.resolve(for: pending, in: [pending], watermarks: [:], selfUsername: me), .none)

        var failed = message("m-2")
        failed.failed = true
        failed.receivedBy = ["bob": 1]
        XCTAssertEqual(ReceiptState.resolve(for: failed, in: [failed], watermarks: [:], selfUsername: me), .none,
                       "a failed message never shows delivered, even with a receipt on file")
    }

    func testReceiptMakesDelivered() {
        var m = message("m-1")
        m.receivedBy = ["bob": 1_700_000_000_000]
        XCTAssertEqual(ReceiptState.resolve(for: m, in: [m], watermarks: [:], selfUsername: me), .delivered)
    }

    func testWatermarkAtOrAfterMessageMakesSeen() {
        let messages = [message("m-1"), message("m-2"), message("m-3", mine: false)]
        let watermarks = ["bob": "m-2"]
        XCTAssertEqual(ReceiptState.resolve(for: messages[0], in: messages, watermarks: watermarks, selfUsername: me), .seen)
        XCTAssertEqual(ReceiptState.resolve(for: messages[1], in: messages, watermarks: watermarks, selfUsername: me), .seen)
    }

    func testWatermarkBeforeMessageIsNotSeen() {
        let messages = [message("m-1"), message("m-2")]
        let watermarks = ["bob": "m-1"]
        XCTAssertEqual(ReceiptState.resolve(for: messages[1], in: messages, watermarks: watermarks, selfUsername: me), .sent)
    }

    func testOwnWatermarkDoesNotCountAsSeen() {
        let messages = [message("m-1")]
        XCTAssertEqual(ReceiptState.resolve(for: messages[0], in: messages, watermarks: [me: "m-1"], selfUsername: me), .sent)
    }

    func testWatermarkMatchesSentIdThroughXmppId() {
        var echoed = message("archive-9")
        echoed.xmppId = "send-text-message-1"
        let messages = [echoed]
        XCTAssertEqual(
            ReceiptState.resolve(for: echoed, in: messages, watermarks: ["bob": "send-text-message-1"], selfUsername: me),
            .seen
        )
    }

    func testSeenOutranksDelivered() {
        var m = message("m-1")
        m.receivedBy = ["bob": 1]
        let messages = [m]
        XCTAssertEqual(ReceiptState.resolve(for: m, in: messages, watermarks: ["bob": "m-1"], selfUsername: me), .seen)
    }
}
