import XCTest
@testable import XMPPChatUI
@testable import XMPPChatCore

/// L2 ViewModel tests for `MessageListViewModel`.
///
/// `MessageListViewModel` owns the message-list scroll lifecycle:
/// pagination state, auto-load tracking, scroll-position anchoring
/// across history fetches. Each piece has a small, observable
/// contract that's easy to regress and tedious to surface manually.
/// These tests pin the contract without spinning up a SwiftUI view
/// hierarchy.
///
/// Equivalent layer on Android is the Compose UI test suite under
/// `ethora-component/src/androidTest/`. iOS doesn't ship
/// ViewInspector or a snapshot framework yet, so we exercise the
/// ViewModel directly. When/if we add view-rendering tests, they
/// belong in this same target.
@MainActor
final class MessageListViewModelTests: XCTestCase {

    private func makeViewModel(roomJID: String = "a@conference.test") -> MessageListViewModel {
        MessageListViewModel(roomJID: roomJID, chatRoomViewModel: nil)
    }

    private func makeMessage(id: String, body: String = "hello", timestamp: Int64 = 1_000) -> Message {
        Message(
            id: id,
            user: User(id: "u-1@xmpp.test"),
            date: Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0),
            body: body,
            roomJid: "a@conference.test",
            timestamp: timestamp
        )
    }

    // MARK: - Initial state

    func testInitialStateIsEmptyAndIdle() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.messages.count, 0)
        XCTAssertFalse(vm.isLoading)
        XCTAssertFalse(vm.isLoadingMore)
        XCTAssertFalse(vm.isHistoryComplete)
        XCTAssertEqual(vm.pageSize, 30, "default pageSize is 30 — the React MessageList parity value")
        XCTAssertFalse(vm.isAutoLoadInProgress)
        XCTAssertEqual(vm.currentConsecutiveAutoLoads, 0)
    }

    // MARK: - State transitions

    func testSetLoadingFlipsIsLoadingFlag() {
        let vm = makeViewModel()
        vm.setLoading(true)
        XCTAssertTrue(vm.isLoading)
        vm.setLoading(false)
        XCTAssertFalse(vm.isLoading)
    }

    func testSetLoadingMoreFlipsIsLoadingMoreFlag() {
        // isLoadingMore drives the "loading older history" spinner at
        // the top of the list — distinct from isLoading which is the
        // initial-load placeholder.
        let vm = makeViewModel()
        vm.setLoadingMore(true)
        XCTAssertTrue(vm.isLoadingMore)
        vm.setLoadingMore(false)
        XCTAssertFalse(vm.isLoadingMore)
    }

    func testSetHistoryCompleteFlipsIsHistoryCompleteFlag() {
        // Once MAM signals no-more-history, the UI must stop trying
        // to auto-fetch on scroll-to-top. The flag is the single
        // source of truth.
        let vm = makeViewModel()
        vm.setHistoryComplete(true)
        XCTAssertTrue(vm.isHistoryComplete)
        vm.setHistoryComplete(false)
        XCTAssertFalse(vm.isHistoryComplete)
    }

    // MARK: - updateMessages

    func testUpdateMessagesReplacesTheList() {
        let vm = makeViewModel()
        vm.updateMessages([makeMessage(id: "m-1"), makeMessage(id: "m-2", timestamp: 2_000)])
        XCTAssertEqual(vm.messages.map { $0.id }, ["m-1", "m-2"])

        // Subsequent update fully replaces — this is the documented
        // contract (the method comment + signature both say it's a
        // replacement, not a merge; pagination merges happen at the
        // ChatRoomViewModel layer).
        vm.updateMessages([makeMessage(id: "m-3", timestamp: 3_000)])
        XCTAssertEqual(vm.messages.map { $0.id }, ["m-3"])
    }

    // MARK: - Scroll position anchoring

    func testSaveAndGetScrollPositionRoundTripsValues() {
        // Scroll position is captured before loading older history
        // so the visible row stays visible after the new rows
        // prepend at the top. Regression here causes the chat to
        // "jump" on every history fetch.
        let vm = makeViewModel()
        XCTAssertNil(vm.getScrollPositionInfo())

        vm.saveScrollPosition(top: 120.5, height: 800.0)
        let info = vm.getScrollPositionInfo()
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.top, 120.5)
        XCTAssertEqual(info?.height, 800.0)
    }

    func testClearScrollPositionInfoDropsTheStoredValues() {
        let vm = makeViewModel()
        vm.saveScrollPosition(top: 50, height: 400)
        vm.clearScrollPositionInfo()
        XCTAssertNil(vm.getScrollPositionInfo())
    }

    // MARK: - Auto-load tracking

    func testResetAutoLoadTrackingClearsInProgressAndCounter() {
        // After resetAutoLoadTracking, isAutoLoadInProgress = false
        // and currentConsecutiveAutoLoads = 0 — the user scrolling
        // away from the top must always permit a fresh auto-load
        // budget.
        let vm = makeViewModel()
        vm.resetAutoLoadTracking()
        XCTAssertFalse(vm.isAutoLoadInProgress)
        XCTAssertEqual(vm.currentConsecutiveAutoLoads, 0)
        XCTAssertEqual(vm.maxAutoLoads, 3, "auto-load cap matches the documented constant")
    }

    // MARK: - getPreviousMessageCount

    func testGetPreviousMessageCountReturnsNilWhenNoFetchHasBeenInitiated() {
        // Before fetchHistory has ever been called, there's nothing
        // to anchor against. Returning nil (vs 0) lets callers
        // distinguish "no fetch yet" from "fetched with empty pool".
        let vm = makeViewModel()
        XCTAssertNil(vm.getPreviousMessageCount())
    }
}
