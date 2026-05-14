import XCTest
@testable import XMPPChatCore

/// Regression tests for the live-message dispatcher in
/// `StanzaHandlers.onRealtimeMessage`.
///
/// The dispatcher is called for EVERY incoming `<message/>`. Stanzas
/// that have a dedicated downstream handler — delete, edit, reaction —
/// must be skipped here, otherwise their inner `<body/>` leaks through
/// as a phantom incoming message. The reproducer was a stray "wow"
/// bubble appearing on every delete, because `deleteMessage` sends
/// `<body>wow</body><delete id='…'/>` on the wire (matching the
/// React / Android shape).
///
/// The pure-state side of these tests is enough — we don't need a live
/// XMPPClient. `StanzaHandlers` accepts a nil client (the dispatcher
/// methods don't dereference it).
@MainActor
final class StanzaHandlersTests: XCTestCase {

    // MARK: - Helpers

    private func makeHandlers() -> StanzaHandlers {
        // Pass nil — `onRealtimeMessage` doesn't dereference `client`.
        StanzaHandlers(client: nil)
    }

    private func deleteStanza(targetId: String = "to-be-deleted") -> XMPPStanza {
        // Shape sent by `SendTextMessage.deleteMessage`. The literal
        // `<body>wow</body>` is intentional — it matches React and the
        // server expects the body to be present. The receive-side
        // guard is the one we test.
        XMPPStanza(
            name: "message",
            attributes: [
                "id": "deleteMessageStanza",
                "from": "room1@conference.test/alice",
                "to": "me@xmpp.test",
                "type": "groupchat",
            ],
            children: [
                XMPPStanza(name: "body", text: "wow"),
                XMPPStanza(name: "delete", attributes: ["id": targetId]),
                XMPPStanza(name: "stanza-id", attributes: [
                    "id": "archive-1",
                    "by": "room1@conference.test",
                ]),
            ]
        )
    }

    private func reactionStanza() -> XMPPStanza {
        XMPPStanza(
            name: "message",
            attributes: [
                "id": "message-reaction-1700000000000",
                "from": "room1@conference.test/alice",
                "type": "groupchat",
            ],
            children: [
                XMPPStanza(name: "body", text: "wow"),
                XMPPStanza(
                    name: "reactions",
                    attributes: ["id": "target-msg"],
                    children: [XMPPStanza(name: "thumbsup")]
                ),
                XMPPStanza(name: "stanza-id", attributes: [
                    "id": "archive-2",
                    "by": "room1@conference.test",
                ]),
            ]
        )
    }

    private func editStanza() -> XMPPStanza {
        XMPPStanza(
            name: "message",
            attributes: [
                "id": "edit-message-1700000000000",
                "from": "room1@conference.test/alice",
                "type": "groupchat",
            ],
            children: [
                XMPPStanza(name: "body", text: "wow"),
                XMPPStanza(name: "replace", attributes: [
                    "id": "target-msg",
                    "text": "updated body",
                ]),
                XMPPStanza(name: "stanza-id", attributes: [
                    "id": "archive-3",
                    "by": "room1@conference.test",
                ]),
            ]
        )
    }

    // MARK: - onRealtimeMessage filter

    func testDeleteStanzaIsNotSurfacedAsIncomingMessage() {
        // Reproducer for the "wow" phantom-message bug: a delete-stanza
        // contains a literal `<body>wow</body>` on the wire, and if
        // `onRealtimeMessage` parses it as a plain message, that "wow"
        // bubble shows up in the chat right after the user deletes a
        // message.
        let handlers = makeHandlers()
        var received: [Message] = []
        handlers.onMessageReceived = { message, _ in
            received.append(message)
        }

        handlers.onRealtimeMessage(deleteStanza())

        XCTAssertTrue(received.isEmpty,
                      "delete-stanza must NOT surface via onRealtimeMessage — it has a dedicated handler")
    }

    func testReactionStanzaIsNotSurfacedAsIncomingMessage() {
        let handlers = makeHandlers()
        var received: [Message] = []
        handlers.onMessageReceived = { message, _ in
            received.append(message)
        }

        handlers.onRealtimeMessage(reactionStanza())

        XCTAssertTrue(received.isEmpty,
                      "reaction stanza must NOT surface via onRealtimeMessage")
    }

    func testEditStanzaIsNotSurfacedAsIncomingMessage() {
        let handlers = makeHandlers()
        var received: [Message] = []
        handlers.onMessageReceived = { message, _ in
            received.append(message)
        }

        handlers.onRealtimeMessage(editStanza())

        XCTAssertTrue(received.isEmpty,
                      "edit stanza must NOT surface via onRealtimeMessage")
    }

    // MARK: - Companion: dedicated handlers DO fire

    func testDedicatedDeleteHandlerFiresForDeleteStanza() {
        // Sanity check: the same stanza that onRealtimeMessage rejects
        // is the one `onDeleteMessage` consumes. Together with the test
        // above, this proves the dispatch is complete (live deletes
        // still propagate; only the phantom side-effect is gone).
        let handlers = makeHandlers()
        var deletedTuples: [(String, String)] = []
        handlers.onMessageDeleted = { roomJID, messageId in
            deletedTuples.append((roomJID, messageId))
        }

        handlers.onDeleteMessage(deleteStanza(targetId: "msg-99"))

        XCTAssertEqual(deletedTuples.count, 1)
        XCTAssertEqual(deletedTuples.first?.0, "room1@conference.test")
        XCTAssertEqual(deletedTuples.first?.1, "msg-99")
    }
}
