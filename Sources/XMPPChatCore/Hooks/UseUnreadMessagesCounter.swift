//
//  UseUnreadMessagesCounter.swift
//  XMPPChatCore
//
//  Unread messages counter
//

import Foundation
import Combine

@MainActor
public class UnreadMessagesCounter: ObservableObject {
    @Published public var unreadCounts: [String: Int] = [:] // roomJID: count
    @Published public var lastReadTimestamps: [String: Date] = [:] // roomJID: timestamp

    private let unreadCountsKey = "ethora_unread_counts"
    private let lastReadKey = "ethora_unread_last_read"

    public init() {
        if let unreadData = UserDefaults.standard.data(forKey: unreadCountsKey),
           let decodedUnread = try? JSONDecoder().decode([String: Int].self, from: unreadData) {
            unreadCounts = decodedUnread
        }
        if let lastReadData = UserDefaults.standard.data(forKey: lastReadKey),
           let decodedLastRead = try? JSONDecoder().decode([String: Date].self, from: lastReadData) {
            lastReadTimestamps = decodedLastRead
        }
    }
    
    public func increment(forRoom roomJID: String) {
        unreadCounts[roomJID] = (unreadCounts[roomJID] ?? 0) + 1
        persist()
    }
    
    public func markAsRead(forRoom roomJID: String) {
        unreadCounts[roomJID] = 0
        lastReadTimestamps[roomJID] = Date()
        persist()
    }
    
    public func getUnreadCount(forRoom roomJID: String) -> Int {
        return unreadCounts[roomJID] ?? 0
    }
    
    public func getTotalUnreadCount() -> Int {
        return unreadCounts.values.reduce(0, +)
    }
    
    public func reset(forRoom roomJID: String) {
        unreadCounts.removeValue(forKey: roomJID)
        lastReadTimestamps.removeValue(forKey: roomJID)
        persist()
    }
    
    public func resetAll() {
        unreadCounts.removeAll()
        lastReadTimestamps.removeAll()
        persist()
    }

    private func persist() {
        if let unreadData = try? JSONEncoder().encode(unreadCounts) {
            UserDefaults.standard.set(unreadData, forKey: unreadCountsKey)
        }
        if let lastReadData = try? JSONEncoder().encode(lastReadTimestamps) {
            UserDefaults.standard.set(lastReadData, forKey: lastReadKey)
        }
    }
}
