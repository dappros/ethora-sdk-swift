import XCTest
@testable import XMPPChatCore

@MainActor
final class UnreadStateBridgeTests: XCTestCase {
    override func setUp() async throws {
        RoomStore.shared.clearAll()
    }

    override func tearDown() async throws {
        RoomStore.shared.clearAll()
    }

    func testDerivesTotalUnreadAcrossRooms() {
        let roomA = makeRoom(id: "a", jid: "a@conference.test", unread: 3)
        let roomB = makeRoom(id: "b", jid: "b@conference.test", unread: 5)
        RoomStore.shared.addRoom(roomA)
        RoomStore.shared.addRoom(roomB)

        let bridge = UnreadStateBridge(roomStore: RoomStore.shared)

        XCTAssertEqual(bridge.totalUnreadCount, 8)
        XCTAssertEqual(bridge.unreadCount(for: roomA.jid), 3)
        XCTAssertEqual(bridge.unreadCount(for: roomB.jid), 5)
    }

    func testUnreadCountForMissingRoomIsZero() {
        let bridge = UnreadStateBridge(roomStore: RoomStore.shared)
        XCTAssertEqual(bridge.unreadCount(for: "missing@conference.test"), 0)
    }

    func testReactsToRoomStoreUpdatesAndNormalizesNegative() async {
        let room = makeRoom(id: "a", jid: "a@conference.test", unread: 0)
        RoomStore.shared.addRoom(room)

        let bridge = UnreadStateBridge(roomStore: RoomStore.shared)
        XCTAssertEqual(bridge.totalUnreadCount, 0)

        RoomStore.shared.updateUnreadCount(roomJID: room.jid, count: 4)
        await waitForMainRunloop()
        XCTAssertEqual(bridge.totalUnreadCount, 4)
        XCTAssertEqual(bridge.unreadByRoom[room.jid], 4)

        RoomStore.shared.updateUnreadCount(roomJID: room.jid, count: -7)
        await waitForMainRunloop()
        XCTAssertEqual(bridge.totalUnreadCount, 0)
        XCTAssertEqual(bridge.unreadByRoom[room.jid], 0)
    }

    func testBadgeBindingOnlyFiresOnTotalChange() async {
        let room = makeRoom(id: "a", jid: "a@conference.test", unread: 1)
        RoomStore.shared.addRoom(room)

        let bridge = UnreadStateBridge(roomStore: RoomStore.shared)
        var received: [Int] = []
        bridge.bindBadge { value in
            received.append(value)
        }

        RoomStore.shared.updateUnreadCount(roomJID: room.jid, count: 1)
        await waitForMainRunloop()
        XCTAssertTrue(received.isEmpty)

        RoomStore.shared.updateUnreadCount(roomJID: room.jid, count: 2)
        await waitForMainRunloop()

        RoomStore.shared.updateUnreadCount(roomJID: room.jid, count: 2)
        await waitForMainRunloop()
        XCTAssertEqual(received, [2])

        RoomStore.shared.updateUnreadCount(roomJID: room.jid, count: 0)
        await waitForMainRunloop()
        XCTAssertEqual(received, [2, 0])
    }

    private func makeRoom(id: String, jid: String, unread: Int) -> Room {
        Room(
            id: id,
            jid: jid,
            name: id,
            title: id,
            unreadMessages: unread
        )
    }

    private func waitForMainRunloop() async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}
