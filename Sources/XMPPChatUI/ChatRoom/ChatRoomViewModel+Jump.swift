//
//  ChatRoomViewModel+Jump.swift
//  XMPPChatUI
//
//  Brings one archived message on screen. Translated from useJumpToMessage.ts
//  and helpers/jumpWindow.ts. A message already in the live list is scrolled to.
//  Otherwise a window of history around it is fetched by MAM and shown in place
//  of the live list until the reader jumps back to the latest messages.
//

import Foundation
import Combine
import XMPPChatCore

extension ChatRoomViewModel {

    /// Messages above and below the target in a jump window (web JUMP_WINDOW_BEFORE/AFTER).
    static let jumpWindowBefore = 10
    static let jumpWindowAfter = 10
    /// Half-width of the time lookup for a message that has no archive id.
    static let timeLookupWindow: TimeInterval = 5
    static let timeLookupMax = 50
    static let highlightDuration: TimeInterval = 1.5
    static let noticeDuration: TimeInterval = 4

    /// What the list shows: the jump window while one is open, else the live list.
    var displayedMessages: [Message] {
        jumpWindow ?? messages
    }

    var isShowingJumpWindow: Bool {
        jumpWindow != nil
    }

    /// Subscribes to jump requests for this room. A request that is already
    /// pending when the chat opens is taken at once.
    func observePendingJumps() {
        pendingJumpSubscription = RoomStore.shared.$pendingJump
            .receive(on: DispatchQueue.main)
            .sink { [weak self] jump in
                guard let self, let jump, ChatRoomViewModel.sameRoom(jump.roomJID, self.room.jid) else { return }
                self.fulfilJump(jump)
            }
    }

    /// Returns from a jump window to the live list ("Jump to latest", or sending).
    func leaveJumpWindow() {
        guard jumpWindow != nil else { return }
        jumpWindow = nil
        jumpScrollTarget = nil
    }

    /// Takes a request and starts fulfilling it. A newer request replaces an older one.
    func fulfilJump(_ jump: PendingJump) {
        if RoomStore.shared.pendingJump == jump {
            RoomStore.shared.pendingJump = nil
        }
        guard !jump.isExpired() else { return }
        jumpTask?.cancel()
        jumpTask = Task { @MainActor [weak self] in
            await self?.performJump(jump)
        }
    }

    // MARK: - Fulfilling

    @MainActor
    func performJump(_ jump: PendingJump) async {
        // Already on screen (in the window or the live list): just scroll to it.
        if let message = ChatRoomViewModel.findMessage(jump, in: displayedMessages) {
            reveal(message.id)
            return
        }
        // In the live list but a window is open: go back to the live list.
        if let message = ChatRoomViewModel.findMessage(jump, in: messages) {
            leaveJumpWindow()
            reveal(message.id)
            return
        }

        let window: [Message]?
        if let archiveId = jump.ids.compactMap(MamCursor.archiveId).first {
            window = await fetchWindow(around: archiveId, jump: jump)
        } else if let createdAt = jump.createdAt {
            window = await fetchTimeLookup(around: createdAt, jump: jump)
        } else {
            window = nil
        }

        guard let window, let target = ChatRoomViewModel.findMessage(jump, in: window) else {
            showNotice("This message is not in the chat history.")
            return
        }
        jumpWindow = window
        reveal(target.id)
    }

    /// Two MAM queries in parallel: the rows before the target, and the target
    /// with the rows after it (the `after` cursor starts one microsecond below the target).
    @MainActor
    private func fetchWindow(around archiveId: Int64, jump: PendingJump) async -> [Message]? {
        async let older = client.operations.fetchHistoryPage(
            chatJID: room.jid,
            max: ChatRoomViewModel.jumpWindowBefore,
            before: archiveId
        )
        async let newer = client.operations.fetchHistoryPage(
            chatJID: room.jid,
            max: ChatRoomViewModel.jumpWindowAfter + 1,
            after: archiveId - 1
        )
        let olderPage = await older
        let newerPage = await newer
        // Both failed: the archive could not be asked. A page that answered
        // with nothing is still an answer.
        guard olderPage.succeeded || newerPage.succeeded else {
            showNotice("Could not load the message. Check the connection and try again.")
            return nil
        }
        return ChatRoomViewModel.mergeWindow(olderPage.messages + newerPage.messages)
    }

    /// A message without an archive id is located by its time, then by its body.
    @MainActor
    private func fetchTimeLookup(around createdAt: Date, jump: PendingJump) async -> [Message]? {
        let page = await client.operations.fetchHistoryPage(
            chatJID: room.jid,
            max: ChatRoomViewModel.timeLookupMax,
            start: MessageSearchDates.isoString(createdAt.addingTimeInterval(-ChatRoomViewModel.timeLookupWindow)),
            end: MessageSearchDates.isoString(createdAt.addingTimeInterval(ChatRoomViewModel.timeLookupWindow))
        )
        guard page.succeeded else {
            showNotice("Could not load the message. Check the connection and try again.")
            return nil
        }
        return ChatRoomViewModel.mergeWindow(page.messages)
    }

    /// Scrolls the list to a message and flashes it. The list does the scrolling
    /// (ChatRoomView observes `jumpScrollTarget`).
    @MainActor
    private func reveal(_ messageId: String) {
        jumpScrollTarget = messageId
        highlightedMessageId = messageId
        let duration = ChatRoomViewModel.highlightDuration
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if self?.highlightedMessageId == messageId {
                self?.highlightedMessageId = nil
            }
        }
    }

    @MainActor
    private func showNotice(_ text: String) {
        jumpNotice = text
        jumpNoticeTask?.cancel()
        jumpNoticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(ChatRoomViewModel.noticeDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.jumpNotice = nil
        }
    }

    // MARK: - Pure helpers

    /// Room JIDs compare without a resource part (`room@conf/nick`).
    static func sameRoom(_ lhs: String, _ rhs: String) -> Bool {
        lhs.components(separatedBy: "/").first == rhs.components(separatedBy: "/").first
    }

    /// Finds the message a jump asks for: by id first (archive, stanza, message or
    /// client xmpp id), then by body and a time within a few seconds.
    static func findMessage(_ jump: PendingJump, in messages: [Message]) -> Message? {
        for id in jump.ids {
            if let message = messages.first(where: { $0.id == id || $0.xmppId == id }) {
                return message
            }
        }
        guard let body = jump.body, let createdAt = jump.createdAt else { return nil }
        return messages.first { message in
            guard message.body == body else { return false }
            let timestamp = message.timestamp.map { Date(timeIntervalSince1970: Double($0) / 1000) } ?? message.date
            return abs(timestamp.timeIntervalSince(createdAt)) <= timeLookupWindow
        }
    }

    /// Joins the two halves of a window: no duplicates, oldest first.
    static func mergeWindow(_ messages: [Message]) -> [Message] {
        var seen = Set<String>()
        let unique = messages.filter { seen.insert($0.id).inserted }
        return unique.sorted { ($0.timestamp ?? 0) < ($1.timestamp ?? 0) }
    }
}
