import XCTest
@testable import XMPPChatCore

/// Reactions and thread references. Pure-function tests: no live client.
/// Covers the reaction reducer, the `<reactions>` stanza readers (live and MAM
/// wrapper), and the `mainMessage` JSON used by replies.
@MainActor
final class ReactionsAndThreadsTests: XCTestCase {

    // MARK: - Helpers

    private func user(_ id: String = "alice") -> User {
        User(id: id, name: "Alice A", firstName: "Alice", lastName: "A", xmppUsername: id)
    }

    private func message(
        id: String,
        body: String = "hello",
        isReply: Bool? = nil,
        showInChannel: String? = nil,
        mainMessage: String? = nil,
        timestamp: Int64? = nil
    ) -> Message {
        Message(
            id: id,
            user: user(),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            body: body,
            roomJid: "room1@conference.test",
            timestamp: timestamp,
            showInChannel: showInChannel,
            isReply: isReply,
            mainMessage: mainMessage
        )
    }

    /// Live `<message id="message-reaction:…">` as the server relays it (MUC).
    private func liveReactionStanza(
        targetId: String = "42",
        reactor: String = "bob@xmpp.test",
        emoji: [String] = ["+1", "heart"],
        timestamp: String = "1700000000123456789"
    ) -> XMPPStanza {
        XMPPStanza(
            name: "message",
            attributes: [
                "id": "message-reaction:1700000000123",
                "from": "room1@conference.test/bob",
                "type": "groupchat",
            ],
            children: [
                XMPPStanza(
                    name: "reactions",
                    attributes: ["id": targetId, "from": reactor, "xmlns": "urn:xmpp:reactions:0"],
                    children: emoji.map { XMPPStanza(name: "reaction", text: $0) }
                ),
                XMPPStanza(
                    name: "data",
                    attributes: ["senderFirstName": "Bob", "senderLastName": "B"]
                ),
                XMPPStanza(
                    name: "stanza-id",
                    attributes: ["id": timestamp, "by": "room1@conference.test"]
                ),
            ]
        )
    }

    // MARK: - MessageReactions reducer

    func testReactorKeyIsLocalpart() {
        XCTAssertEqual(MessageReactions.reactorKey(fromJID: "bob@xmpp.test/phone"), "bob")
        XCTAssertEqual(MessageReactions.reactorKey(fromJID: "bob"), "bob")
    }

    func testApplyStoresReactorSetByLocalpart() {
        let map = MessageReactions.apply(
            nil,
            reactorKey: "bob",
            emoji: ["+1"],
            data: ["senderFirstName": "Bob", "senderLastName": "B"],
            timestamp: 10
        )
        XCTAssertEqual(map?["bob"]?.emoji, ["+1"])
        XCTAssertEqual(map?["bob"]?.timestamp, 10)
    }

    func testNewestTimestampWinsPerReactor() {
        let first = MessageReactions.apply(nil, reactorKey: "bob", emoji: ["+1"], data: [:], timestamp: 20)
        // Older update arrives later (MAM replay): ignored.
        let stale = MessageReactions.apply(first, reactorKey: "bob", emoji: ["heart"], data: [:], timestamp: 10)
        XCTAssertEqual(stale?["bob"]?.emoji, ["+1"])
        // Newer update wins.
        let fresh = MessageReactions.apply(first, reactorKey: "bob", emoji: ["heart"], data: [:], timestamp: 30)
        XCTAssertEqual(fresh?["bob"]?.emoji, ["heart"])
    }

    func testEmptyListIsRemovalMarkerThatBlocksOlderAdd() {
        let added = MessageReactions.apply(nil, reactorKey: "bob", emoji: ["+1"], data: [:], timestamp: 10)
        let removed = MessageReactions.apply(added, reactorKey: "bob", emoji: [], data: [:], timestamp: 20)
        XCTAssertEqual(removed?["bob"]?.emoji, [])
        // An add older than the removal must not bring the reaction back.
        let replayedAdd = MessageReactions.apply(removed, reactorKey: "bob", emoji: ["+1"], data: [:], timestamp: 15)
        XCTAssertEqual(replayedAdd?["bob"]?.emoji, [])
        XCTAssertTrue(MessageReactions.summaries(replayedAdd).isEmpty)
    }

    func testPollutingKeysAreRejected() {
        XCTAssertNil(MessageReactions.apply(nil, reactorKey: "__proto__", emoji: ["+1"], data: [:], timestamp: nil))
        XCTAssertNil(MessageReactions.apply(nil, reactorKey: "constructor", emoji: ["+1"], data: [:], timestamp: nil))
        XCTAssertNil(MessageReactions.apply(nil, reactorKey: "", emoji: ["+1"], data: [:], timestamp: nil))
    }

    func testSummariesGroupByShortcodeWithNamesAndSkipRemovals() {
        let map: [String: ReactionMessage] = [
            "bob": ReactionMessage(emoji: ["+1", "heart"], data: ["senderFirstName": "Bob", "senderLastName": "B"], timestamp: 1),
            "carol": ReactionMessage(emoji: ["+1"], data: ["senderFirstName": "Carol", "senderLastName": "C"], timestamp: 2),
            "dan": ReactionMessage(emoji: [], data: [:], timestamp: 3),
        ]
        let summaries = MessageReactions.summaries(map)
        XCTAssertEqual(summaries.map(\.shortcode), ["+1", "heart"])
        XCTAssertEqual(summaries[0].count, 2)
        XCTAssertEqual(summaries[0].reactorKeys, ["bob", "carol"])
        XCTAssertEqual(summaries[0].reactorNames, ["Bob B", "Carol C"])
        XCTAssertEqual(summaries[1].count, 1)
    }

    func testDisplayNameFallsBackToKey() {
        XCTAssertEqual(MessageReactions.displayName(for: [:], fallback: "bob"), "bob")
    }

    // MARK: - EmojiShortcodes

    func testQuickDefaultsResolveToGlyphs() {
        XCTAssertEqual(EmojiShortcodes.defaultQuickReactions, ["+1", "heart", "joy", "open_mouth", "cry", "pray"])
        for shortcode in EmojiShortcodes.defaultQuickReactions {
            XCTAssertNotNil(EmojiShortcodes.glyph(for: shortcode), shortcode)
        }
        XCTAssertEqual(EmojiShortcodes.glyph(for: "+1"), "👍")
        XCTAssertNil(EmojiShortcodes.glyph(for: "not-a-real-shortcode"))
    }

    // MARK: - Reaction stanza readers

    func testLiveReactionStanzaParsesTextValuesReactorAndTimestamp() {
        let handlers = StanzaHandlers(client: nil)
        var received: [ReactionUpdate] = []
        handlers.onReactionReceived = { received.append($0) }

        handlers.onReactionMessage(liveReactionStanza())

        XCTAssertEqual(received.count, 1)
        let update = received[0]
        XCTAssertEqual(update.roomJID, "room1@conference.test")
        XCTAssertEqual(update.messageId, "42")
        XCTAssertEqual(update.emoji, ["+1", "heart"])
        XCTAssertEqual(update.reactorJID, "bob@xmpp.test")
        XCTAssertEqual(update.data["senderFirstName"], "Bob")
        XCTAssertEqual(update.data["senderLastName"], "B")
        XCTAssertEqual(update.timestamp, 1_700_000_000_123_456_789)
    }

    func testEmptyReactionStanzaIsARemoval() {
        let handlers = StanzaHandlers(client: nil)
        var received: [ReactionUpdate] = []
        handlers.onReactionReceived = { received.append($0) }

        handlers.onReactionMessage(liveReactionStanza(emoji: []))

        XCTAssertEqual(received.first?.emoji, [])
    }

    func testMamReactionWrapperParsesSameShape() {
        let inner = liveReactionStanza(targetId: "7", emoji: ["joy"])
        let mam = XMPPStanza(
            name: "message",
            attributes: ["from": "room1@conference.test"],
            children: [
                XMPPStanza(
                    name: "result",
                    attributes: ["xmlns": "urn:xmpp:mam:2", "id": "archive-9"],
                    children: [
                        XMPPStanza(
                            name: "forwarded",
                            children: [XMPPStanza(name: "message", attributes: inner.attributes, children: inner.children)]
                        )
                    ]
                )
            ]
        )
        let handlers = StanzaHandlers(client: nil)
        var received: [ReactionUpdate] = []
        handlers.onReactionReceived = { received.append($0) }

        handlers.onReactionHistory(mam)

        XCTAssertEqual(received.first?.messageId, "7")
        XCTAssertEqual(received.first?.emoji, ["joy"])
        XCTAssertEqual(received.first?.reactorJID, "bob@xmpp.test")
    }

    func testReactionWithoutTargetIsIgnored() {
        let handlers = StanzaHandlers(client: nil)
        var received: [ReactionUpdate] = []
        handlers.onReactionReceived = { received.append($0) }

        handlers.onReactionMessage(liveReactionStanza(targetId: ""))

        XCTAssertTrue(received.isEmpty)
    }

    // MARK: - Thread references

    func testMainMessageJSONRoundTripsThroughParse() {
        let parent = message(id: "1700000000000", body: "Parent text")
        let json = ThreadReference.mainMessageJSON(for: parent)

        let parsed = ThreadReference.parse(json)
        XCTAssertEqual(parsed?.id, "1700000000000")
        XCTAssertEqual(parsed?.text, "Parent text")
        XCTAssertEqual(parsed?.roomJid, "room1@conference.test")
        XCTAssertEqual(parsed?.userName, "Alice A")
        XCTAssertEqual(parsed?.createdAt, "2023-11-14T22:13:20.000Z")
    }

    func testMainMessageJSONHasWebKeys() throws {
        let json = ThreadReference.mainMessageJSON(for: message(id: "1"))
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        for key in ["text", "id", "userName", "createdAt", "imageLocation", "imagePreview",
                    "mimeType", "size", "duration", "waveForm", "attachmentId", "wrappable",
                    "nftActionType", "contractAddress", "roomJid", "nftId"] {
            XCTAssertNotNil(object[key], key)
        }
    }

    func testParseRejectsEmptyAndNonObjectValues() {
        XCTAssertNil(ThreadReference.parse(nil))
        XCTAssertNil(ThreadReference.parse(""))
        XCTAssertNil(ThreadReference.parse("   "))
        XCTAssertNil(ThreadReference.parse("123"))
        XCTAssertNil(ThreadReference.parse("not json"))
    }

    func testParentStubBuildsFromMainMessage() {
        let parent = message(id: "5", body: "root body")
        let reply = message(
            id: "6",
            isReply: true,
            mainMessage: ThreadReference.mainMessageJSON(for: parent)
        )
        let stub = ThreadReference.parentStub(for: reply)
        XCTAssertEqual(stub?.id, "5")
        XCTAssertEqual(stub?.body, "root body")
        XCTAssertNil(ThreadReference.parentStub(for: message(id: "9")))
    }

    func testThreadRepliesFilterByParentAndOrderOldestFirst() {
        let root = "100"
        let json = ThreadReference.mainMessageJSON(for: message(id: root))
        let later = message(id: "201", isReply: true, mainMessage: json, timestamp: 300)
        let earlier = message(id: "200", isReply: true, mainMessage: json, timestamp: 200)
        let otherThread = message(
            id: "300", isReply: true,
            mainMessage: ThreadReference.mainMessageJSON(for: message(id: "999")),
            timestamp: 250
        )
        let plain = message(id: "400", timestamp: 260)

        let replies = ThreadReference.threadReplies(of: root, in: [later, otherThread, plain, earlier])

        XCTAssertEqual(replies.map(\.id), ["200", "201"])
    }

    func testRepliesByParentIncludesChannelShownReplies() {
        let root = "100"
        let json = ThreadReference.mainMessageJSON(for: message(id: root))
        let threadOnly = message(id: "201", isReply: true, mainMessage: json)
        let shownInChannel = message(id: "202", isReply: true, showInChannel: "true", mainMessage: json)

        let buckets = ThreadReference.repliesByParent([threadOnly, shownInChannel])

        XCTAssertEqual(buckets[root]?.map(\.id), ["201", "202"])
    }

    func testChannelReplyStillOpensItsParentThread() {
        let root = "100"
        let shown = message(
            id: "202", isReply: true, showInChannel: "true",
            mainMessage: ThreadReference.mainMessageJSON(for: message(id: root))
        )
        XCTAssertEqual(ThreadReference.threadParentId(of: shown), root)
        XCTAssertNil(ThreadReference.threadParentId(of: message(id: "101")))
    }
}
