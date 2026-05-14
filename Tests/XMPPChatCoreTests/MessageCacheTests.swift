import XCTest
@testable import XMPPChatCore

/// Hermetic L1 tests for `MessageCache` — the per-room message
/// persistence layer that backs the fast-load path on cold-start.
/// Contract pinned here:
///   • Save + load round-trip is lossless for the codable surface of
///     `Message` (including the `isDeleted` tombstone).
///   • Per-room isolation: writing to room A doesn't leak into room B.
///   • The 100-message per-room cap drops the OLDEST entries when
///     overflowed (suffix-keep behaviour).
///   • `clearMessages(forRoomJID:)` removes the cached entry; the next
///     `loadMessages` returns nil rather than an empty array.
///   • `clearAll()` wipes every cached room — used by `clearUser()`.
@MainActor
final class MessageCacheTests: XCTestCase {

    override func setUp() async throws {
        MessageCache.shared.clearAll()
        // Restore defaults — earlier tests may have changed cache caps.
        MessageCache.shared.configure(
            maxRooms: 50,
            maxMessagesPerRoom: 100,
            maxTotalMessages: 5_000,
            maxAgeDays: nil
        )
    }

    override func tearDown() async throws {
        MessageCache.shared.clearAll()
    }

    // MARK: - Helpers

    /// Each test uses a distinct room JID prefix so leftover state from
    /// a prior failed run can't contaminate the next.
    private func jid(_ suffix: String, file: StaticString = #file, line: UInt = #line) -> String {
        "cache-test-\(suffix)@conference.test"
    }

    private func makeMessage(id: String, roomJID: String, body: String = "msg", timestamp: Int64 = 1_000) -> Message {
        Message(
            id: id,
            user: User(id: "u-1@xmpp.test"),
            date: Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0),
            body: body,
            roomJid: roomJID,
            timestamp: timestamp
        )
    }

    // MARK: - Round-trip

    func testSaveAndLoadMessagesRoundTripsContent() {
        let roomJID = jid("round-trip")
        let messages = [
            makeMessage(id: "m-1", roomJID: roomJID, body: "first", timestamp: 1_000),
            makeMessage(id: "m-2", roomJID: roomJID, body: "second", timestamp: 2_000),
            makeMessage(id: "m-3", roomJID: roomJID, body: "third", timestamp: 3_000),
        ]

        MessageCache.shared.saveMessages(messages, forRoomJID: roomJID)
        let loaded = MessageCache.shared.loadMessages(forRoomJID: roomJID)

        XCTAssertEqual(loaded?.map { $0.id }, ["m-1", "m-2", "m-3"])
        XCTAssertEqual(loaded?.map { $0.body }, ["first", "second", "third"])
        XCTAssertEqual(loaded?.map { $0.timestamp }, [1_000, 2_000, 3_000])
    }

    func testLoadMessagesReturnsNilForUnknownRoom() {
        XCTAssertNil(MessageCache.shared.loadMessages(forRoomJID: jid("never-written")))
    }

    func testHasCachedMessagesReflectsSaveState() {
        let roomJID = jid("has-cached")
        XCTAssertFalse(MessageCache.shared.hasCachedMessages(forRoomJID: roomJID))

        MessageCache.shared.saveMessages(
            [makeMessage(id: "m-1", roomJID: roomJID)],
            forRoomJID: roomJID
        )
        XCTAssertTrue(MessageCache.shared.hasCachedMessages(forRoomJID: roomJID))
    }

    // MARK: - Tombstone survives the cache

    func testTombstonedMessageRoundTripsPreservingIsDeletedFlag() {
        // Tombstones must persist so that a cold-start hydrate keeps
        // the "message deleted" placeholder visible. If we lost
        // isDeleted on save+load, the message would resurface with
        // empty body and confusing UI.
        let roomJID = jid("tombstone")
        let tombstone = Message(
            id: "deleted-m",
            user: User(id: "u-1@xmpp.test"),
            date: Date(timeIntervalSince1970: 1),
            body: "",
            roomJid: roomJID,
            isMediafile: "false",
            timestamp: 1_000,
            isDeleted: true
        )

        MessageCache.shared.saveMessages([tombstone], forRoomJID: roomJID)
        let loaded = MessageCache.shared.loadMessages(forRoomJID: roomJID)

        XCTAssertEqual(loaded?.count, 1)
        XCTAssertEqual(loaded?.first?.id, "deleted-m")
        XCTAssertEqual(loaded?.first?.isDeleted, true)
        XCTAssertEqual(loaded?.first?.body, "")
    }

    // MARK: - Per-room isolation

    func testSaveMessagesIsScopedPerRoom() {
        let roomA = jid("iso-a")
        let roomB = jid("iso-b")

        MessageCache.shared.saveMessages(
            [makeMessage(id: "a-1", roomJID: roomA, body: "in A")],
            forRoomJID: roomA
        )
        MessageCache.shared.saveMessages(
            [makeMessage(id: "b-1", roomJID: roomB, body: "in B")],
            forRoomJID: roomB
        )

        XCTAssertEqual(MessageCache.shared.loadMessages(forRoomJID: roomA)?.map { $0.id }, ["a-1"])
        XCTAssertEqual(MessageCache.shared.loadMessages(forRoomJID: roomB)?.map { $0.id }, ["b-1"])
    }

    // MARK: - Per-room cap

    func testSaveMessagesKeepsTheNewestEntriesWhenOverflowingPerRoomCap() {
        // Tighten the cap so the test stays small. Cap → keep last N.
        MessageCache.shared.configure(maxMessagesPerRoom: 3)
        let roomJID = jid("cap")

        let overflow = (1...6).map { i in
            makeMessage(id: "m-\(i)", roomJID: roomJID, body: "msg \(i)", timestamp: Int64(i) * 1_000)
        }
        MessageCache.shared.saveMessages(overflow, forRoomJID: roomJID)

        let loaded = MessageCache.shared.loadMessages(forRoomJID: roomJID) ?? []
        XCTAssertEqual(loaded.count, 3, "cap must drop oldest, keep newest 3")
        XCTAssertEqual(loaded.map { $0.id }, ["m-4", "m-5", "m-6"],
                       "suffix(maxCachedMessagesPerRoom) — newest preserved")
    }

    // MARK: - Cached timestamp

    func testGetCachedTimestampReturnsLastSavedMessageTimestamp() {
        let roomJID = jid("timestamp")
        MessageCache.shared.saveMessages(
            [
                makeMessage(id: "m-1", roomJID: roomJID, timestamp: 1_000),
                makeMessage(id: "m-2", roomJID: roomJID, timestamp: 2_000),
            ],
            forRoomJID: roomJID
        )
        XCTAssertEqual(MessageCache.shared.getCachedTimestamp(forRoomJID: roomJID), 2_000)
    }

    // MARK: - Eviction

    func testClearMessagesForRoomRemovesOnlyThatRoom() {
        let roomA = jid("clear-a")
        let roomB = jid("clear-b")
        MessageCache.shared.saveMessages([makeMessage(id: "a-1", roomJID: roomA)], forRoomJID: roomA)
        MessageCache.shared.saveMessages([makeMessage(id: "b-1", roomJID: roomB)], forRoomJID: roomB)

        MessageCache.shared.clearMessages(forRoomJID: roomA)

        XCTAssertNil(MessageCache.shared.loadMessages(forRoomJID: roomA))
        XCTAssertNotNil(MessageCache.shared.loadMessages(forRoomJID: roomB),
                        "clearing room A must not touch room B")
    }

    func testClearAllWipesEveryCachedRoom() {
        // clearAll is invoked from `UserStore.clearUser()` so a logout
        // doesn't leak the previous user's messages into the next
        // session's cache.
        let roomA = jid("clearall-a")
        let roomB = jid("clearall-b")
        MessageCache.shared.saveMessages([makeMessage(id: "a-1", roomJID: roomA)], forRoomJID: roomA)
        MessageCache.shared.saveMessages([makeMessage(id: "b-1", roomJID: roomB)], forRoomJID: roomB)

        MessageCache.shared.clearAll()

        XCTAssertNil(MessageCache.shared.loadMessages(forRoomJID: roomA))
        XCTAssertNil(MessageCache.shared.loadMessages(forRoomJID: roomB))
        XCTAssertFalse(MessageCache.shared.hasCachedMessages(forRoomJID: roomA))
        XCTAssertFalse(MessageCache.shared.hasCachedMessages(forRoomJID: roomB))
    }
}
