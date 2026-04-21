//
//  UseUnreadStateBridge.swift
//  XMPPChatCore
//
//  Host-facing unread helper for badge propagation and room unread access.
//

import Foundation
import Combine

@MainActor
public final class UnreadStateBridge: ObservableObject {
    @Published public private(set) var totalUnreadCount: Int = 0
    @Published public private(set) var unreadByRoom: [String: Int] = [:]

    private let roomStore: RoomStore
    private var cancellables: Set<AnyCancellable> = []
    private var badgeHandler: ((Int) -> Void)?
    private var lastNotifiedBadgeCount: Int?

    public init(roomStore: RoomStore = .shared) {
        self.roomStore = roomStore
        recalculate(from: roomStore.rooms)

        roomStore.$rooms
            .sink { [weak self] rooms in
                self?.recalculate(from: rooms)
            }
            .store(in: &cancellables)
    }

    public func unreadCount(for roomJID: String) -> Int {
        unreadByRoom[roomJID] ?? 0
    }

    public func bindBadge(_ handler: @escaping (Int) -> Void) {
        badgeHandler = handler
    }

    public func unbindBadge() {
        badgeHandler = nil
        lastNotifiedBadgeCount = nil
    }

    private func recalculate(from rooms: [String: Room]) {
        let mappedUnread = rooms.reduce(into: [String: Int]()) { partial, entry in
            partial[entry.key] = max(0, entry.value.unreadMessages)
        }

        let total = mappedUnread.values.reduce(0, +)

        unreadByRoom = mappedUnread
        totalUnreadCount = total

        guard total != lastNotifiedBadgeCount else { return }
        lastNotifiedBadgeCount = total
        badgeHandler?(total)
    }
}
