import XCTest
@testable import XMPPChatUI
@testable import XMPPChatCore

/// The search state machine (useMessageSearch.ts rules) and the jump helpers
/// (useJumpToMessage.ts matching). Network is replaced by an injected fetcher.
@MainActor
final class MessageSearchModelTests: XCTestCase {

    /// Records the queries the model sends. Only touched on the main actor.
    private final class QueryLog {
        var queries: [MessageSearchQuery] = []
    }

    private func hit(_ id: String, body: String = "hello") -> MessageSearchHit {
        MessageSearchHit(id: id, chatId: "room1", chatType: "group", room: "room1@c", from: "", fromUserId: "", body: body, messageId: "", stanzaId: "", createdAt: "")
    }

    private func page(_ ids: [String], total: Int, nextOffset: Int, offset: Int = 0) -> MessageSearchPage {
        MessageSearchPage(items: ids.map { hit($0) }, total: total, offset: offset, limit: 20, nextOffset: nextOffset)
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    // MARK: - State

    func testFirstPageReplacesAndAppendDeduplicates() {
        var state = MessageSearchState()
        state.receive(page: page(["1", "2"], total: 5, nextOffset: 2), append: false)
        XCTAssertEqual(state.items.map(\.id), ["1", "2"])
        XCTAssertTrue(state.hasMore)

        state.receive(page: page(["2", "3"], total: 5, nextOffset: 4, offset: 2), append: true)
        XCTAssertEqual(state.items.map(\.id), ["1", "2", "3"], "a hit seen twice is listed once")
        XCTAssertEqual(state.nextOffset, 4)
        XCTAssertEqual(state.status, .done)
    }

    func testResetClearsEverything() {
        var state = MessageSearchState()
        state.receive(page: page(["1"], total: 1, nextOffset: 1), append: false)
        state.reset()
        XCTAssertEqual(state, MessageSearchState())
        XCTAssertFalse(state.hasMore)
    }

    // MARK: - Model

    func testShortQueryDoesNotSearch() async {
        let log = QueryLog()
        let model = MessageSearchModel(roomName: "room1", debounce: 0) { query in
            log.queries.append(query)
            return self.page([], total: 0, nextOffset: 0)
        }
        model.text = " h "
        model.scheduleSearch()
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertTrue(log.queries.isEmpty)
        XCTAssertEqual(model.state.status, .idle)
    }

    func testChatScopeSearchesTheOpenRoomOnce() async {
        let log = QueryLog()
        let model = MessageSearchModel(roomName: "room1", debounce: 0) { query in
            log.queries.append(query)
            return self.page(["7"], total: 1, nextOffset: 1)
        }
        model.text = "hello"
        model.scheduleSearch()
        let done = await waitUntil { model.state.status == .done }
        XCTAssertTrue(done)
        XCTAssertEqual(log.queries.count, 1)
        XCTAssertEqual(log.queries.first?.q, "hello")
        XCTAssertEqual(log.queries.first?.chatId, "room1")
        XCTAssertEqual(model.state.items.map(\.id), ["7"])
    }

    func testAllChatsScopeSendsNoRoom() async {
        let log = QueryLog()
        let model = MessageSearchModel(roomName: nil, debounce: 0) { query in
            log.queries.append(query)
            return self.page([], total: 0, nextOffset: 0)
        }
        XCTAssertEqual(model.scope, .all)
        model.text = "hi there"
        model.scheduleSearch()
        _ = await waitUntil { model.state.status == .done }
        XCTAssertNil(log.queries.first?.chatId)
    }

    func testBackwardsDayRangeSendsNothing() async {
        let log = QueryLog()
        let model = MessageSearchModel(roomName: "room1", debounce: 0) { query in
            log.queries.append(query)
            return self.page([], total: 0, nextOffset: 0)
        }
        model.text = "hello"
        model.sinceDay = Date(timeIntervalSince1970: 2_000_000_000)
        model.untilDay = Date(timeIntervalSince1970: 1_000_000_000)
        model.scheduleSearch()
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertTrue(log.queries.isEmpty)
        XCTAssertTrue(model.hasBackwardsRange)
    }

    func testLoadMoreAsksFromTheServerOffset() async {
        let log = QueryLog()
        let model = MessageSearchModel(roomName: "room1", debounce: 0) { query in
            log.queries.append(query)
            if query.offset == 0 {
                return self.page(["1", "2"], total: 4, nextOffset: 2)
            }
            return self.page(["3", "4"], total: 4, nextOffset: 4, offset: query.offset)
        }
        model.text = "hello"
        model.scheduleSearch()
        _ = await waitUntil { model.state.status == .done }
        XCTAssertTrue(model.hasMore)

        model.loadMore()
        _ = await waitUntil { model.state.items.count == 4 }
        XCTAssertEqual(log.queries.last?.offset, 2)
        XCTAssertEqual(model.state.items.map(\.id), ["1", "2", "3", "4"])
        XCTAssertFalse(model.hasMore)
    }

    func testFailureThenRetry() async {
        var calls = 0
        let model = MessageSearchModel(roomName: "room1", debounce: 0) { _ in
            calls += 1
            if calls == 1 { throw MessageSearchAPIError.networkError("offline") }
            return MessageSearchPage(items: [MessageSearchHit(id: "9", chatId: "", chatType: "", room: "", from: "", fromUserId: "", body: "ok", messageId: "", stanzaId: "", createdAt: "")], total: 1, offset: 0, limit: 20, nextOffset: 1)
        }
        model.text = "hello"
        model.scheduleSearch()
        _ = await waitUntil { model.state.status == .error }
        XCTAssertEqual(model.state.status, .error)

        model.retry()
        _ = await waitUntil { model.state.status == .done }
        XCTAssertEqual(model.state.items.map(\.id), ["9"])
    }

    // MARK: - Jump helpers

    private func message(_ id: String, body: String = "hi", timestamp: Int64 = 1_700_000_000_000, xmppId: String? = nil) -> Message {
        Message(id: id, user: User(id: "u1"), date: Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000), body: body, roomJid: "r@c", timestamp: timestamp, xmppId: xmppId)
    }

    func testFindMessageByIdThenByBodyAndTime() {
        let messages = [message("1700000000000001", xmppId: "client-1"), message("1700000000000002", body: "target", timestamp: 1_700_000_000_000)]
        let byXmpp = PendingJump(roomJID: "r@c", ids: ["client-1"])
        XCTAssertEqual(ChatRoomViewModel.findMessage(byXmpp, in: messages)?.id, "1700000000000001")

        let byContent = PendingJump(roomJID: "r@c", ids: ["unknown"], createdAt: Date(timeIntervalSince1970: 1_700_000_002), body: "target")
        XCTAssertEqual(ChatRoomViewModel.findMessage(byContent, in: messages)?.id, "1700000000000002")

        let far = PendingJump(roomJID: "r@c", ids: [], createdAt: Date(timeIntervalSince1970: 1_800_000_000), body: "target")
        XCTAssertNil(ChatRoomViewModel.findMessage(far, in: messages))
    }

    func testMergeWindowDropsDuplicatesAndSortsOldestFirst() {
        let merged = ChatRoomViewModel.mergeWindow([
            message("3", timestamp: 300),
            message("1", timestamp: 100),
            message("3", timestamp: 300),
            message("2", timestamp: 200),
        ])
        XCTAssertEqual(merged.map(\.id), ["1", "2", "3"])
    }

    func testSameRoomIgnoresResourcePart() {
        XCTAssertTrue(ChatRoomViewModel.sameRoom("room@conf.test/nick", "room@conf.test"))
        XCTAssertFalse(ChatRoomViewModel.sameRoom("other@conf.test", "room@conf.test"))
    }
}
