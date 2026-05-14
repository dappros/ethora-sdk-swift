import XCTest
@testable import XMPPChatCore

/// Hermetic L1 tests for the singleton `RoomStore`.
///
/// Mirrors the bug-class coverage the Android SDK ships in
/// `RoomStoreTest` / `MessageStoreTest`, ported to the iOS API shape:
/// iOS keeps messages on the `Room` itself (`room.messages`) rather
/// than in a separate `MessageStore`, so the equivalent reducer paths
/// live on `RoomStore.addMessage(_:toRoomJID:)`,
/// `setRoomMessages(roomJID:messages:)`, and `recomputeUnreadForRoom`.
///
/// See `QA_SCENARIOS.md` in the ethora monorepo for the cross-platform
/// cluster catalog these tests target (clusters A, D, F).
@MainActor
final class RoomStoreTests: XCTestCase {

    override func setUp() async throws {
        RoomStore.shared.clearAll()
    }

    override func tearDown() async throws {
        RoomStore.shared.clearAll()
    }

    // MARK: - Helpers

    private func makeRoom(
        id: String,
        jid: String? = nil,
        unread: Int = 0,
        lastViewed: Int64? = nil
    ) -> Room {
        // Init order: lastViewedTimestamp precedes unreadMessages.
        Room(
            id: id,
            jid: jid ?? "\(id)@conference.test",
            name: "room-\(id)",
            title: "Room \(id)",
            lastViewedTimestamp: lastViewed,
            unreadMessages: unread
        )
    }

    private func makeMessage(
        id: String,
        roomJID: String = "a@conference.test",
        body: String = "hello",
        timestamp: Int64 = 1_000,
        senderLocal: String = "other-user",
        pending: Bool? = nil,
        isDeleted: Bool? = nil,
        isSystemMessage: String? = nil
    ) -> Message {
        // `recomputeUnreadForRoom` derives own-vs-other from
        // `User.xmppUsername` (not `id`), so seed both — id is set as a
        // fallback but the filter actually reads xmppUsername.
        Message(
            id: id,
            user: User(id: "\(senderLocal)@xmpp.test", xmppUsername: "\(senderLocal)@xmpp.test"),
            date: Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0),
            body: body,
            roomJid: roomJID,
            isSystemMessage: isSystemMessage,
            pending: pending,
            timestamp: timestamp,
            isDeleted: isDeleted
        )
    }

    // MARK: - addRoom / updateRoom (Cluster A)

    func testAddRoomInsertsNewRoomKeyedByJID() {
        let room = makeRoom(id: "a")
        RoomStore.shared.addRoom(room)
        XCTAssertEqual(RoomStore.shared.rooms.count, 1)
        XCTAssertNotNil(RoomStore.shared.rooms[room.jid])
    }

    func testAddRoomPreservesExistingUnreadAndLastViewedOnUpsert() {
        // The contract in `RoomStore.addRoom`: if we already have this
        // room, preserve the client-tracked unread state. REST refreshes
        // shouldn't wipe the badge. Same contract Telegram ships.
        var first = makeRoom(id: "a")
        first.unreadMessages = 5
        first.lastViewedTimestamp = 999_999
        RoomStore.shared.addRoom(first)

        // Simulate a REST refresh — same room arrives without unread fields.
        var refreshed = makeRoom(id: "a")
        refreshed.unreadMessages = 0
        refreshed.lastViewedTimestamp = 0
        RoomStore.shared.addRoom(refreshed)

        let stored = RoomStore.shared.rooms[first.jid]
        XCTAssertEqual(stored?.unreadMessages, 5, "REST refresh must not wipe client unread")
        XCTAssertEqual(stored?.lastViewedTimestamp, 999_999, "REST refresh must not wipe lastViewed")
    }

    func testHiddenRoomJIDsBlocksReAddViaAPI() {
        // After the user leaves a room, REST `/chats/my` can still
        // return it. The hidden-JIDs guard must block re-add until
        // the user explicitly rejoins.
        let room = makeRoom(id: "a")
        RoomStore.shared.addRoom(room)
        RoomStore.shared.hideRoom(jid: room.jid)
        XCTAssertNil(RoomStore.shared.rooms[room.jid])

        // Naive REST refresh — should be ignored.
        RoomStore.shared.addRoom(room)
        XCTAssertNil(
            RoomStore.shared.rooms[room.jid],
            "hidden room must NOT come back via addRoom while hidden flag is set"
        )

        // Explicit unhide brings it back.
        RoomStore.shared.unhideRoom(jid: room.jid)
        RoomStore.shared.addRoom(room)
        XCTAssertNotNil(RoomStore.shared.rooms[room.jid])
    }

    // MARK: - setActiveRoom multi-room transitions (Cluster A continuation)

    func testSetActiveRoomTransitionsAcrossABBackToA() {
        // Open A → open B → re-enter A. The activeRoomJID pointer
        // must reflect each transition, including the re-entry.
        let a = makeRoom(id: "a")
        let b = makeRoom(id: "b")
        RoomStore.shared.addRoom(a)
        RoomStore.shared.addRoom(b)

        RoomStore.shared.setActiveRoom(a.jid)
        XCTAssertEqual(RoomStore.shared.activeRoomJID, a.jid)

        RoomStore.shared.setActiveRoom(b.jid)
        XCTAssertEqual(RoomStore.shared.activeRoomJID, b.jid)

        RoomStore.shared.setActiveRoom(a.jid)
        XCTAssertEqual(
            RoomStore.shared.activeRoomJID, a.jid,
            "re-entering A after a B detour must register as a transition"
        )
    }

    func testSetActiveRoomNilClearsPointerWithoutDroppingRooms() {
        RoomStore.shared.addRoom(makeRoom(id: "a"))
        RoomStore.shared.addRoom(makeRoom(id: "b"))
        RoomStore.shared.setActiveRoom("a@conference.test")

        RoomStore.shared.setActiveRoom(nil)

        XCTAssertNil(RoomStore.shared.activeRoomJID)
        XCTAssertEqual(RoomStore.shared.rooms.count, 2, "rooms list must survive the active-room clear")
    }

    // MARK: - addMessage idempotency + cross-room (Cluster D + A)

    func testAddMessageIsIdempotentOnDuplicateId() {
        // MAM replay can deliver the same id twice. The second add
        // must not append a second copy. iOS dedup is by `message.id`
        // existence check.
        let room = makeRoom(id: "a")
        RoomStore.shared.addRoom(room)
        let msg = makeMessage(id: "m-1", roomJID: room.jid)

        RoomStore.shared.addMessage(msg, toRoomJID: room.jid)
        RoomStore.shared.addMessage(msg, toRoomJID: room.jid)

        XCTAssertEqual(
            RoomStore.shared.rooms[room.jid]?.messages.count, 1,
            "duplicate id must not be re-appended"
        )
    }

    func testAddMessageCrossRoomIsolation() {
        // Adding to room A must not touch room B's message list — the
        // store's per-room indexing protects this, lock in the contract.
        let a = makeRoom(id: "a")
        let b = makeRoom(id: "b")
        RoomStore.shared.addRoom(a)
        RoomStore.shared.addRoom(b)
        RoomStore.shared.setRoomMessages(
            roomJID: b.jid,
            messages: [makeMessage(id: "b-1", roomJID: b.jid)]
        )

        for i in 1...5 {
            RoomStore.shared.addMessage(
                makeMessage(id: "a-\(i)", roomJID: a.jid, timestamp: Int64(1_000 * i)),
                toRoomJID: a.jid
            )
        }

        XCTAssertEqual(RoomStore.shared.rooms[a.jid]?.messages.count, 5)
        XCTAssertEqual(
            RoomStore.shared.rooms[b.jid]?.messages.map { $0.id }, ["b-1"],
            "messages in room B must be unaffected by sends to room A"
        )
    }

    func testAddMessageSortsByTimestamp() {
        // The reducer sorts by timestamp ascending — out-of-order
        // arrivals (MAM replay, retries) must end up chronologically.
        let room = makeRoom(id: "a")
        RoomStore.shared.addRoom(room)
        RoomStore.shared.addMessage(makeMessage(id: "m-3", roomJID: room.jid, timestamp: 3_000), toRoomJID: room.jid)
        RoomStore.shared.addMessage(makeMessage(id: "m-1", roomJID: room.jid, timestamp: 1_000), toRoomJID: room.jid)
        RoomStore.shared.addMessage(makeMessage(id: "m-2", roomJID: room.jid, timestamp: 2_000), toRoomJID: room.jid)

        XCTAssertEqual(
            RoomStore.shared.rooms[room.jid]?.messages.map { $0.id },
            ["m-1", "m-2", "m-3"]
        )
    }

    func testAddMessageUpdatesLastMessagePreviewAndTimestamp() {
        // Catches the regression class where the room-list preview drifted
        // from the actual most-recent message body.
        let room = makeRoom(id: "a")
        RoomStore.shared.addRoom(room)

        let newest = makeMessage(id: "m-1", roomJID: room.jid, body: "hello there", timestamp: 1_234_567)
        RoomStore.shared.addMessage(newest, toRoomJID: room.jid)

        XCTAssertEqual(RoomStore.shared.rooms[room.jid]?.lastMessage?.body, "hello there")
        XCTAssertEqual(RoomStore.shared.rooms[room.jid]?.lastMessageTimestamp, 1_234_567)
    }

    // MARK: - deleteMessage / setRoomMessages (Cluster F)

    func testSetRoomMessagesRoundTripsContent() {
        // Fast-load contract: when MessageCache hydrates messages via
        // setRoomMessages, getMessages observes them immediately.
        let room = makeRoom(id: "a")
        RoomStore.shared.addRoom(room)

        let seeded = [
            makeMessage(id: "c-1", roomJID: room.jid, body: "one", timestamp: 1_000),
            makeMessage(id: "c-2", roomJID: room.jid, body: "two", timestamp: 2_000),
            makeMessage(id: "c-3", roomJID: room.jid, body: "three", timestamp: 3_000),
        ]
        RoomStore.shared.setRoomMessages(roomJID: room.jid, messages: seeded)

        XCTAssertEqual(
            RoomStore.shared.rooms[room.jid]?.messages.map { $0.id },
            ["c-1", "c-2", "c-3"]
        )
    }

    func testDeleteMessageTombstonesRow() {
        // Tombstone contract (cross-platform parity with React + Kotlin):
        // deleteMessage flips `isDeleted = true` and clears body/media
        // fields, but the row stays in the list so the bubble can render a
        // "deleted" placeholder and reply anchors that reference this id
        // don't dangle.
        let room = makeRoom(id: "a")
        RoomStore.shared.addRoom(room)
        RoomStore.shared.setRoomMessages(
            roomJID: room.jid,
            messages: [
                makeMessage(id: "doomed", roomJID: room.jid, body: "secret", timestamp: 1_000),
                makeMessage(id: "survivor", roomJID: room.jid, body: "kept", timestamp: 2_000),
            ]
        )

        RoomStore.shared.deleteMessage(roomJID: room.jid, messageId: "doomed")

        let stored = RoomStore.shared.rooms[room.jid]?.messages ?? []
        XCTAssertEqual(stored.map { $0.id }, ["doomed", "survivor"],
                       "row is tombstoned in place, not removed")

        let tombstone = stored.first { $0.id == "doomed" }
        XCTAssertEqual(tombstone?.isDeleted, true)
        XCTAssertEqual(tombstone?.body, "", "body must be cleared so the old content can't leak")
        XCTAssertEqual(tombstone?.isMediafile, "false", "media flag is cleared to suppress attachment UI")
        XCTAssertNil(tombstone?.mimetype)
        XCTAssertNil(tombstone?.location)
        XCTAssertNil(tombstone?.locationPreview)
        XCTAssertNil(tombstone?.fileName)
        XCTAssertNil(tombstone?.reaction)

        // Identity-preserving fields stay intact so threading/ordering
        // anchors keep working.
        XCTAssertEqual(tombstone?.timestamp, 1_000)
        XCTAssertEqual(tombstone?.roomJid, room.jid)
    }

    func testDeleteMessageIsNoOpForUnknownIds() {
        // No matching id → list is left exactly as it was. Important so a
        // delete-stanza for a message we never received (e.g. arrived out
        // of order, or for a different device's local-only draft) doesn't
        // mutate state.
        let room = makeRoom(id: "a")
        RoomStore.shared.addRoom(room)
        let seeded = [
            makeMessage(id: "m-1", roomJID: room.jid, timestamp: 1_000),
            makeMessage(id: "m-2", roomJID: room.jid, timestamp: 2_000),
        ]
        RoomStore.shared.setRoomMessages(roomJID: room.jid, messages: seeded)

        RoomStore.shared.deleteMessage(roomJID: room.jid, messageId: "ghost")

        let stored = RoomStore.shared.rooms[room.jid]?.messages ?? []
        XCTAssertEqual(stored.map { $0.id }, ["m-1", "m-2"])
        XCTAssertEqual(stored.compactMap { $0.isDeleted }.count, 0,
                       "no row should be flagged as deleted")
    }

    // MARK: - recomputeUnreadForRoom math (Cluster E)

    func testRecomputeUnreadForActiveRoomZeroesUnread() {
        // Active-room rule: an active room must always read as 0
        // unread, regardless of incoming-message volume.
        let room = makeRoom(id: "a", unread: 5)
        RoomStore.shared.addRoom(room)
        RoomStore.shared.setActiveRoom(room.jid)

        RoomStore.shared.recomputeUnreadForRoom(jid: room.jid, currentUserLocal: "me")

        XCTAssertEqual(RoomStore.shared.rooms[room.jid]?.unreadMessages, 0)
    }

    func testRecomputeUnreadExcludesOwnPendingSystemAndDeletedMessages() {
        // The countable filter on `recomputeUnreadForRoom` skips:
        // own messages, pending, system, deleted, delimiter, no-body.
        // Catches the field-bug class where own MAM-replayed messages
        // counted as unread after re-login.
        //
        // `addRoom` auto-seeds `lastViewedTimestamp` to "now" for
        // first-time rooms, so we explicitly reset it to 0 after add
        // to test the "fresh room counts all countable" branch.
        let room = makeRoom(id: "a")
        RoomStore.shared.addRoom(room)
        RoomStore.shared.setLastViewedTimestamp(roomJID: room.jid, timestamp: 0)

        // Use far-future timestamps so they survive any addRoom auto-seed
        // even if the lastViewed reset above didn't take.
        let base: Int64 = 10_000_000_000_000
        let messages = [
            makeMessage(id: "real", roomJID: room.jid, body: "real one", timestamp: base + 1),
            makeMessage(id: "own", roomJID: room.jid, body: "mine", timestamp: base + 2, senderLocal: "me"),
            makeMessage(id: "pending", roomJID: room.jid, body: "queued", timestamp: base + 3, pending: true),
            makeMessage(id: "system", roomJID: room.jid, body: "joined", timestamp: base + 4, isSystemMessage: "true"),
            makeMessage(id: "deleted", roomJID: room.jid, body: "gone", timestamp: base + 5, isDeleted: true),
        ]
        RoomStore.shared.setRoomMessages(roomJID: room.jid, messages: messages)

        RoomStore.shared.recomputeUnreadForRoom(jid: room.jid, currentUserLocal: "me")

        XCTAssertEqual(
            RoomStore.shared.rooms[room.jid]?.unreadMessages, 1,
            "only the non-own non-pending non-system non-deleted message counts"
        )
    }

    func testRecomputeUnreadHonorsLastViewedTimestampBoundary() {
        // Only messages strictly newer than lastViewed count — the
        // boundary that prevents MAM replay re-marking history as
        // unread on every re-login.
        let lastViewed: Int64 = 5_000
        let room = makeRoom(id: "a", lastViewed: lastViewed)
        RoomStore.shared.addRoom(room)
        RoomStore.shared.setRoomMessages(
            roomJID: room.jid,
            messages: [
                makeMessage(id: "old", roomJID: room.jid, body: "stale", timestamp: lastViewed - 1_000),
                makeMessage(id: "boundary", roomJID: room.jid, body: "at boundary", timestamp: lastViewed),
                makeMessage(id: "new", roomJID: room.jid, body: "after", timestamp: lastViewed + 1_000),
            ]
        )

        RoomStore.shared.recomputeUnreadForRoom(jid: room.jid, currentUserLocal: "me")

        XCTAssertEqual(
            RoomStore.shared.rooms[room.jid]?.unreadMessages, 1,
            "only messages strictly newer than lastViewed contribute to unread"
        )
    }

    // MARK: - updateMessage (Cluster G)

    func testUpdateMessagePatchesOnlyProvidedFields() {
        // PartialMessageUpdate is the in-place patcher used by edit /
        // delete echo handlers. Each unspecified field must keep its
        // prior value — otherwise an edit-stanza that only carries the
        // new body would silently wipe the message's reactions.
        let room = makeRoom(id: "a")
        RoomStore.shared.addRoom(room)
        let original = makeMessage(id: "m-1", roomJID: room.jid, body: "v1", timestamp: 1_000)
        RoomStore.shared.setRoomMessages(roomJID: room.jid, messages: [original])

        var patch = PartialMessageUpdate()
        patch.body = "v2"
        RoomStore.shared.updateMessage(roomJID: room.jid, messageId: "m-1", updates: patch)

        let stored = RoomStore.shared.rooms[room.jid]?.messages.first
        XCTAssertEqual(stored?.body, "v2", "body must reflect the patch")
        XCTAssertEqual(stored?.timestamp, 1_000, "non-patched timestamp must be preserved")
        XCTAssertEqual(stored?.id, "m-1", "id is identity — must never change")
    }

    func testUpdateMessageIsNoOpForUnknownIds() {
        let room = makeRoom(id: "a")
        RoomStore.shared.addRoom(room)
        let seeded = [
            makeMessage(id: "m-1", roomJID: room.jid, body: "v1", timestamp: 1_000),
        ]
        RoomStore.shared.setRoomMessages(roomJID: room.jid, messages: seeded)

        var patch = PartialMessageUpdate()
        patch.body = "ghost-body"
        RoomStore.shared.updateMessage(roomJID: room.jid, messageId: "ghost", updates: patch)

        XCTAssertEqual(RoomStore.shared.rooms[room.jid]?.messages.first?.body, "v1",
                       "unknown id must not touch any existing message body")
    }

    // MARK: - setReactions

    func testSetReactionsAddsReactionToMessage() {
        let room = makeRoom(id: "a")
        RoomStore.shared.addRoom(room)
        RoomStore.shared.setRoomMessages(
            roomJID: room.jid,
            messages: [makeMessage(id: "m-1", roomJID: room.jid)]
        )

        RoomStore.shared.setReactions(
            roomJID: room.jid,
            messageId: "m-1",
            reactions: ["thumbsup"],
            from: "alice@xmpp.test",
            data: [:]
        )

        let stored = RoomStore.shared.rooms[room.jid]?.messages.first
        XCTAssertNotNil(stored?.reaction?["alice"],
                        "reaction must be keyed by the from-JID localpart")
        XCTAssertEqual(stored?.reaction?["alice"]?.emoji, ["thumbsup"])
    }

    func testSetReactionsWithEmptyArrayRemovesUserReaction() {
        // Empty reactions array is the "unreact" signal — must clear
        // this user's entry, not replace it with an empty list.
        let room = makeRoom(id: "a")
        RoomStore.shared.addRoom(room)
        RoomStore.shared.setRoomMessages(
            roomJID: room.jid,
            messages: [makeMessage(id: "m-1", roomJID: room.jid)]
        )
        RoomStore.shared.setReactions(
            roomJID: room.jid,
            messageId: "m-1",
            reactions: ["thumbsup"],
            from: "alice@xmpp.test",
            data: [:]
        )

        RoomStore.shared.setReactions(
            roomJID: room.jid,
            messageId: "m-1",
            reactions: [],
            from: "alice@xmpp.test",
            data: [:]
        )

        let stored = RoomStore.shared.rooms[room.jid]?.messages.first
        XCTAssertNil(stored?.reaction?["alice"],
                     "empty reactions array removes this user's reaction entry")
    }

    func testSetReactionsKeepsOtherUsersReactionsIntact() {
        // Adding/removing alice's reaction must not touch bob's. The
        // reaction map is per-from-localpart.
        let room = makeRoom(id: "a")
        RoomStore.shared.addRoom(room)
        RoomStore.shared.setRoomMessages(
            roomJID: room.jid,
            messages: [makeMessage(id: "m-1", roomJID: room.jid)]
        )
        RoomStore.shared.setReactions(
            roomJID: room.jid,
            messageId: "m-1",
            reactions: ["thumbsup"],
            from: "alice@xmpp.test",
            data: [:]
        )
        RoomStore.shared.setReactions(
            roomJID: room.jid,
            messageId: "m-1",
            reactions: ["heart"],
            from: "bob@xmpp.test",
            data: [:]
        )

        RoomStore.shared.setReactions(
            roomJID: room.jid,
            messageId: "m-1",
            reactions: [],
            from: "alice@xmpp.test",
            data: [:]
        )

        let reactions = RoomStore.shared.rooms[room.jid]?.messages.first?.reaction
        XCTAssertNil(reactions?["alice"])
        XCTAssertEqual(reactions?["bob"]?.emoji, ["heart"],
                       "removing alice must leave bob's reaction in place")
    }

    // MARK: - Tombstone survives setRoomMessages round-trip

    func testTombstonedMessageSurvivesSetRoomMessages() {
        // Reload path: cache hydrate via setRoomMessages must keep
        // isDeleted intact so the bubble keeps showing the placeholder
        // instead of a confusing empty cell.
        let room = makeRoom(id: "a")
        RoomStore.shared.addRoom(room)
        RoomStore.shared.setRoomMessages(
            roomJID: room.jid,
            messages: [
                makeMessage(id: "doomed", roomJID: room.jid, body: "x", timestamp: 1_000, isDeleted: true),
                makeMessage(id: "alive", roomJID: room.jid, body: "y", timestamp: 2_000),
            ]
        )

        let stored = RoomStore.shared.rooms[room.jid]?.messages ?? []
        let doomed = stored.first { $0.id == "doomed" }
        XCTAssertEqual(doomed?.isDeleted, true, "isDeleted must survive the hydrate path")
        XCTAssertEqual(stored.map { $0.id }, ["doomed", "alive"],
                       "setRoomMessages preserves order and keeps the tombstone")
    }
}
