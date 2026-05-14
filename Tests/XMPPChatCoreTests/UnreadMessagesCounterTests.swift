import XCTest
@testable import XMPPChatCore

/// Hermetic L1 tests for `UnreadMessagesCounter` (`UseUnreadMessagesCounter`).
///
/// This is the host-app-facing unread counter that persists per-room
/// unread counts and last-read timestamps to UserDefaults. It's
/// orthogonal to the per-room `unreadMessages` on `Room` (which is
/// derived from message timestamps in `RoomStore`); the counter here
/// is the simpler "I've-been-told-+1, mark-as-read, reset" model the
/// host badge typically binds to.
@MainActor
final class UnreadMessagesCounterTests: XCTestCase {

    private let unreadCountsKey = "ethora_unread_counts"
    private let lastReadKey = "ethora_unread_last_read"

    override func setUp() async throws {
        UserDefaults.standard.removeObject(forKey: unreadCountsKey)
        UserDefaults.standard.removeObject(forKey: lastReadKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: unreadCountsKey)
        UserDefaults.standard.removeObject(forKey: lastReadKey)
    }

    // MARK: - Initial state

    func testFreshCounterIsEmpty() {
        let counter = UnreadMessagesCounter()
        XCTAssertTrue(counter.unreadCounts.isEmpty)
        XCTAssertTrue(counter.lastReadTimestamps.isEmpty)
        XCTAssertEqual(counter.getTotalUnreadCount(), 0)
        XCTAssertEqual(counter.getUnreadCount(forRoom: "anywhere"), 0)
    }

    // MARK: - increment

    func testIncrementBumpsPerRoomCount() {
        let counter = UnreadMessagesCounter()
        counter.increment(forRoom: "room-a")
        counter.increment(forRoom: "room-a")
        counter.increment(forRoom: "room-b")

        XCTAssertEqual(counter.getUnreadCount(forRoom: "room-a"), 2)
        XCTAssertEqual(counter.getUnreadCount(forRoom: "room-b"), 1)
        XCTAssertEqual(counter.getUnreadCount(forRoom: "room-untouched"), 0)
    }

    func testTotalUnreadIsSumAcrossRooms() {
        let counter = UnreadMessagesCounter()
        counter.increment(forRoom: "room-a")
        counter.increment(forRoom: "room-a")
        counter.increment(forRoom: "room-b")
        XCTAssertEqual(counter.getTotalUnreadCount(), 3)
    }

    // MARK: - markAsRead

    func testMarkAsReadZeroesRoomCountAndStampsLastRead() {
        let counter = UnreadMessagesCounter()
        counter.increment(forRoom: "room-a")
        counter.increment(forRoom: "room-a")

        let before = Date()
        counter.markAsRead(forRoom: "room-a")
        let after = Date()

        XCTAssertEqual(counter.getUnreadCount(forRoom: "room-a"), 0,
                       "markAsRead must zero the entry (not delete it)")
        let stamp = counter.lastReadTimestamps["room-a"]
        XCTAssertNotNil(stamp)
        XCTAssertGreaterThanOrEqual(stamp!.timeIntervalSince1970, before.timeIntervalSince1970)
        XCTAssertLessThanOrEqual(stamp!.timeIntervalSince1970, after.timeIntervalSince1970)
    }

    func testMarkAsReadOnlyAffectsTargetedRoom() {
        let counter = UnreadMessagesCounter()
        counter.increment(forRoom: "room-a")
        counter.increment(forRoom: "room-b")

        counter.markAsRead(forRoom: "room-a")

        XCTAssertEqual(counter.getUnreadCount(forRoom: "room-a"), 0)
        XCTAssertEqual(counter.getUnreadCount(forRoom: "room-b"), 1,
                       "marking room-a as read must not touch room-b")
    }

    // MARK: - reset(forRoom:) vs markAsRead

    func testResetRemovesRoomEntirelyUnlikeMarkAsRead() {
        // markAsRead keeps the room in the map at 0; reset deletes the
        // entry entirely. Both bring `getUnreadCount` to 0, but only
        // markAsRead leaves a `lastReadTimestamps` entry.
        let counter = UnreadMessagesCounter()
        counter.increment(forRoom: "room-a")
        counter.markAsRead(forRoom: "room-a")
        XCTAssertNotNil(counter.lastReadTimestamps["room-a"])

        counter.reset(forRoom: "room-a")
        XCTAssertEqual(counter.getUnreadCount(forRoom: "room-a"), 0)
        XCTAssertNil(counter.unreadCounts["room-a"])
        XCTAssertNil(counter.lastReadTimestamps["room-a"])
    }

    // MARK: - resetAll

    func testResetAllClearsAllRoomsAndStamps() {
        let counter = UnreadMessagesCounter()
        counter.increment(forRoom: "room-a")
        counter.increment(forRoom: "room-b")
        counter.markAsRead(forRoom: "room-a")

        counter.resetAll()

        XCTAssertTrue(counter.unreadCounts.isEmpty)
        XCTAssertTrue(counter.lastReadTimestamps.isEmpty)
        XCTAssertEqual(counter.getTotalUnreadCount(), 0)
    }

    // MARK: - Persistence round-trip

    func testStateSurvivesAcrossInstantiations() {
        // The counter persists to UserDefaults on every mutation, so a
        // freshly-constructed instance must rehydrate the prior state.
        // This is how the counter survives app restart.
        do {
            let first = UnreadMessagesCounter()
            first.increment(forRoom: "room-a")
            first.increment(forRoom: "room-a")
            first.increment(forRoom: "room-b")
        }

        let second = UnreadMessagesCounter()
        XCTAssertEqual(second.getUnreadCount(forRoom: "room-a"), 2)
        XCTAssertEqual(second.getUnreadCount(forRoom: "room-b"), 1)
        XCTAssertEqual(second.getTotalUnreadCount(), 3)
    }

    func testResetAllPersistsAcrossInstantiations() {
        // resetAll must also persist — otherwise a logout would only
        // wipe the in-memory state and the next launch would
        // rehydrate stale badges.
        do {
            let first = UnreadMessagesCounter()
            first.increment(forRoom: "room-a")
            first.resetAll()
        }
        let second = UnreadMessagesCounter()
        XCTAssertEqual(second.getTotalUnreadCount(), 0)
    }
}
