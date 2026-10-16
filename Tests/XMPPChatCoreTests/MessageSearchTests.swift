import XCTest
@testable import XMPPChatCore

/// Parsing, query building, the opt-in gate and the date helpers for message search.
/// Mirrors messageSearch.api.test.ts, useMessageSearch.test.tsx and searchFilters.test.ts.
final class MessageSearchTests: XCTestCase {

    private func row(_ id: String, body: String = "hello there", deletedAt: Any = NSNull()) -> [String: Any] {
        [
            "_id": id,
            "chatId": "room1",
            "chatType": "group",
            "room": "room1@conference.test",
            "from": "app_user1@xmpp.test",
            "fromUserId": "user1",
            "body": body,
            "messageId": "m-\(id)",
            "stanzaId": "s-\(id)",
            "createdAt": "2026-07-14T10:00:00.000Z",
            "deletedAt": deletedAt,
        ]
    }

    // MARK: - Parsing

    func testParseKeepsLiveRowsAndDropsDeletedAndEmptyBodies() throws {
        let object: [String: Any] = [
            "items": [
                row("1"),
                row("2", deletedAt: "2026-07-15T00:00:00.000Z"),
                row("3", body: ""),
                row("4"),
            ],
            "total": 42,
            "offset": 0,
            "limit": 20,
        ]
        let page = MessageSearchParser.parsePage(object: object, offset: 0, limit: 20)
        XCTAssertEqual(page.items.map(\.id), ["1", "4"])
        XCTAssertEqual(page.total, 42)
        XCTAssertEqual(page.offset, 0)
        XCTAssertEqual(page.limit, 20)
        XCTAssertEqual(page.items.first?.fromUserId, "user1")
        XCTAssertEqual(page.items.first?.room, "room1@conference.test")
    }

    func testNextOffsetCountsServerRowsNotKeptRows() {
        // Three server rows, one kept: paging must resume after all three.
        let object: [String: Any] = [
            "items": [row("1", deletedAt: "x"), row("2", body: ""), row("3")],
            "total": 10,
        ]
        let page = MessageSearchParser.parsePage(object: object, offset: 20, limit: 20)
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.nextOffset, 23)
        XCTAssertTrue(page.hasMore)
    }

    func testNullDeletedAtIsNotDeleted() {
        let page = MessageSearchParser.parsePage(object: ["items": [row("1", deletedAt: NSNull())], "total": 1], offset: 0, limit: 20)
        XCTAssertEqual(page.items.map(\.id), ["1"])
        XCTAssertFalse(page.hasMore)
    }

    func testParsePageFromData() throws {
        let data = #"{"items":[{"_id":"9","body":"hi","deletedAt":null}],"total":"3","offset":"0","limit":20}"#.data(using: .utf8)!
        let page = try MessageSearchParser.parsePage(data: data, offset: 0, limit: 20)
        XCTAssertEqual(page.items.map(\.body), ["hi"])
        XCTAssertEqual(page.total, 3)
    }

    /// Rows without an id used to share one key (`chatId:`), so distinct hits collided.
    func testHitKeyIsUniqueWhenIdsAreEmpty() {
        let a = MessageSearchHit(id: "", chatId: "r", chatType: "", room: "", from: "", fromUserId: "", body: "first message", messageId: "", stanzaId: "", createdAt: "t1")
        let b = MessageSearchHit(id: "", chatId: "r", chatType: "", room: "", from: "", fromUserId: "", body: "second message", messageId: "", stanzaId: "", createdAt: "t2")
        XCTAssertNotEqual(a.key, b.key)
        let withId = MessageSearchHit(id: "42", chatId: "r", chatType: "", room: "", from: "", fromUserId: "", body: "x", messageId: "", stanzaId: "", createdAt: "")
        XCTAssertEqual(withId.key, "42")
    }

    // MARK: - Query

    func testQueryItemsOmitEmptyOptionals() {
        let bare = MessageSearchQuery(q: "hello", offset: 40).queryItems
        XCTAssertEqual(bare.map(\.name), ["q", "limit", "offset"])
        XCTAssertEqual(bare.first(where: { $0.name == "offset" })?.value, "40")

        let filtered = MessageSearchQuery(q: "hi", chatId: "room1", fromUserId: "u1", since: "a", until: "b").queryItems
        XCTAssertEqual(Set(filtered.map(\.name)), ["q", "limit", "offset", "chatId", "fromUserId", "since", "until"])
    }

    func testSearchEndpointStripsVersionSuffixAndEncodesAppId() {
        let base = URL(string: "https://api.chat.ethora.com/v1")!
        XCTAssertEqual(
            MessageSearchAPI.searchEndpoint(baseURL: base, appId: "app 1")?.absoluteString,
            "https://api.chat.ethora.com/v2/apps/app%201/messages/search"
        )
        let slashed = URL(string: "https://api.chat.ethora.com/V2/")!
        XCTAssertEqual(
            MessageSearchAPI.searchEndpoint(baseURL: slashed, appId: "a")?.absoluteString,
            "https://api.chat.ethora.com/v2/apps/a/messages/search"
        )
    }

    // MARK: - Gate

    func testSearchIsOffByDefaultAndNeedsAppId() {
        var config = ChatConfig()
        XCTAssertFalse(MessageSearchGate.isEnabled(config))
        config.enableMessageSearch = true
        XCTAssertFalse(MessageSearchGate.isEnabled(config), "no appId")
        config.appId = "   "
        XCTAssertFalse(MessageSearchGate.isEnabled(config), "blank appId")
        config.appId = "app"
        XCTAssertTrue(MessageSearchGate.isEnabled(config))
        XCTAssertFalse(MessageSearchGate.isEnabled(nil))
    }

    func testDisableFlagWinsAndHideSearchOnlyHidesTheButton() {
        var config = ChatConfig()
        config.enableMessageSearch = true
        config.appId = "app"
        config.disableMessageSearch = true
        XCTAssertFalse(MessageSearchGate.isEnabled(config))

        config.disableMessageSearch = false
        config.chatHeaderSettings = ChatHeaderSettingsConfig(hideSearch: true)
        XCTAssertTrue(MessageSearchGate.isEnabled(config))
        XCTAssertFalse(MessageSearchGate.isHeaderButtonVisible(config))
    }

    func testSearchFlagsSurviveCodableRoundTrip() throws {
        var config = ChatConfig()
        config.enableMessageSearch = true
        config.disableMessageSearch = false
        config.appId = "app"
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ChatConfig.self, from: data)
        XCTAssertEqual(decoded.enableMessageSearch, true)
        XCTAssertEqual(decoded.disableMessageSearch, false)
        XCTAssertTrue(MessageSearchGate.isEnabled(decoded))
    }

    // MARK: - Dates

    func testDayBoundsCoverTheWholeDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(MessageSearchDates.dayStartISO("2026-07-14", calendar: calendar), "2026-07-14T00:00:00.000Z")
        XCTAssertEqual(MessageSearchDates.dayEndISO("2026-07-14", calendar: calendar), "2026-07-14T23:59:59.999Z")
    }

    func testInvalidAndBackwardsDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertNil(MessageSearchDates.dayStartISO("2026-02-30", calendar: calendar), "no roll-over")
        XCTAssertNil(MessageSearchDates.dayEndISO("14.07.2026", calendar: calendar))
        XCTAssertFalse(MessageSearchDates.isValidDay("2026-7-4"))
        XCTAssertTrue(MessageSearchDates.isBackwardsRange(from: "2026-07-15", to: "2026-07-14"))
        XCTAssertFalse(MessageSearchDates.isBackwardsRange(from: "2026-07-14", to: "2026-07-14"))
        XCTAssertFalse(MessageSearchDates.isBackwardsRange(from: "", to: "2026-07-14"))
    }

    // MARK: - PendingJump

    func testPendingJumpDropsBlankAndDuplicateIds() {
        let jump = PendingJump(roomJID: "r@c", ids: ["", " 5 ", "5", "7"])
        XCTAssertEqual(jump.ids, ["5", "7"])
    }

    func testPendingJumpExpires() {
        let start = Date(timeIntervalSince1970: 1_000)
        let jump = PendingJump(roomJID: "r@c", ids: ["5"], requestedAt: start)
        XCTAssertFalse(jump.isExpired(now: start.addingTimeInterval(59)))
        XCTAssertTrue(jump.isExpired(now: start.addingTimeInterval(61)))
    }
}
