//
//  MessageSearchModel.swift
//  XMPPChatUI
//
//  Debounced, cancellable message search with paging. Translated from
//  src/components/Modals/MessageSearchModal/useMessageSearch.ts
//

import Foundation
import Combine
import XMPPChatCore

/// Where a search looks: the open chat, or every chat the user can see.
public enum MessageSearchScope: Equatable {
    case chat
    case all
}

/// The state of one search, as the modal shows it. Pure value type, so the
/// rules (which responses are kept, how pages are merged) can be tested alone.
public struct MessageSearchState: Equatable {
    public enum Status: Equatable {
        case idle
        case loading
        case loadingMore
        case done
        case error
    }

    public private(set) var status: Status = .idle
    public private(set) var items: [MessageSearchHit] = []
    public private(set) var total: Int = 0
    /// Server rows consumed so far: the offset of the next page.
    public private(set) var nextOffset: Int = 0

    public init() {}

    public var hasMore: Bool { nextOffset < total }

    public mutating func reset() {
        self = MessageSearchState()
    }

    public mutating func startRequest(loadingMore: Bool) {
        status = loadingMore ? .loadingMore : .loading
    }

    /// Applies one page. A page that is appended skips hits already shown, so
    /// a row that moved between two pages is not listed twice.
    public mutating func receive(page: MessageSearchPage, append: Bool) {
        var seen = Set(append ? items.map(\.key) : [])
        var fresh: [MessageSearchHit] = []
        for hit in page.items where !seen.contains(hit.key) {
            seen.insert(hit.key)
            fresh.append(hit)
        }
        items = append ? items + fresh : fresh
        total = page.total
        nextOffset = page.nextOffset
        status = .done
    }

    public mutating func fail() {
        status = .error
    }
}

@MainActor
public final class MessageSearchModel: ObservableObject {

    public typealias Fetcher = (MessageSearchQuery) async throws -> MessageSearchPage

    @Published public var text: String = "" {
        didSet { scheduleSearch() }
    }
    @Published public var scope: MessageSearchScope = .chat {
        didSet { scheduleSearch() }
    }
    /// Sender filter: a room member's `_id`. nil means anyone.
    @Published public var fromUserId: String? {
        didSet { scheduleSearch() }
    }
    /// Day filters. nil means no bound. Each day covers the whole day, in the
    /// reader's time zone.
    @Published public var sinceDay: Date? {
        didSet { scheduleSearch() }
    }
    @Published public var untilDay: Date? {
        didSet { scheduleSearch() }
    }

    @Published public private(set) var state = MessageSearchState()

    /// The open chat's room name, required for `.chat` scope.
    public let roomName: String?

    private let fetch: Fetcher
    private let debounce: TimeInterval
    private var searchTask: Task<Void, Never>?
    private var requestTask: Task<Void, Never>?
    /// Bumped by every new request. A response for an older request is dropped,
    /// so a slow answer to "he" never overwrites the results for "hello".
    private var generation = 0

    public init(
        roomName: String?,
        scope: MessageSearchScope = .chat,
        debounce: TimeInterval = 0.3,
        fetch: @escaping Fetcher = { try await MessageSearchAPI.search($0) }
    ) {
        self.roomName = roomName
        self.scope = roomName == nil ? .all : scope
        self.debounce = debounce
        self.fetch = fetch
    }

    deinit {
        searchTask?.cancel()
        requestTask?.cancel()
    }

    public var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether a request can run now: enough characters, and a room for `.chat`.
    public var isSearchable: Bool {
        trimmedText.count >= MessageSearchQuery.minQueryLength
            && (scope == .all || !(roomName ?? "").isEmpty)
    }

    /// True when the picked range runs backwards: no request is sent for it.
    public var hasBackwardsRange: Bool {
        guard let sinceDay, let untilDay else { return false }
        return Self.dayString(sinceDay) > Self.dayString(untilDay)
    }

    public var hasMore: Bool { state.hasMore }

    /// The query for the current inputs, at the given offset.
    public func makeQuery(offset: Int = 0) -> MessageSearchQuery {
        let chatId: String? = scope == .chat ? roomName : nil
        return MessageSearchQuery(
            q: trimmedText,
            chatId: chatId,
            fromUserId: fromUserId,
            since: sinceDay.flatMap { MessageSearchDates.dayStartISO(Self.dayString($0)) },
            until: untilDay.flatMap { MessageSearchDates.dayEndISO(Self.dayString($0)) },
            offset: offset
        )
    }

    /// Runs the search after the debounce. A newer change cancels the wait and
    /// any request in flight.
    public func scheduleSearch() {
        cancelInFlight()
        guard isSearchable, !hasBackwardsRange else {
            state.reset()
            return
        }
        let current = generation
        let debounce = self.debounce
        searchTask = Task { [weak self] in
            if debounce > 0 {
                try? await Task.sleep(nanoseconds: UInt64(debounce * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await self?.run(offset: 0, generation: current)
        }
    }

    /// The next page of the current search.
    public func loadMore() {
        guard state.status == .done, state.hasMore else { return }
        requestTask?.cancel()
        generation += 1
        let current = generation
        let offset = state.nextOffset
        requestTask = Task { [weak self] in
            await self?.run(offset: offset, generation: current)
        }
    }

    /// Repeats the first page after a failure, without the debounce.
    public func retry() {
        guard isSearchable, !hasBackwardsRange else { return }
        cancelInFlight()
        let current = generation
        requestTask = Task { [weak self] in
            await self?.run(offset: 0, generation: current)
        }
    }

    private func cancelInFlight() {
        searchTask?.cancel()
        requestTask?.cancel()
        generation += 1
    }

    private func run(offset: Int, generation current: Int) async {
        state.startRequest(loadingMore: offset > 0)
        do {
            let page = try await fetch(makeQuery(offset: offset))
            guard current == generation, !Task.isCancelled else { return }
            state.receive(page: page, append: offset > 0)
        } catch {
            guard current == generation, !Task.isCancelled else { return }
            state.fail()
        }
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
