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
    
    public func increment(forRoom roomJID: String) {
        unreadCounts[roomJID] = (unreadCounts[roomJID] ?? 0) + 1
    }
    
    public func markAsRead(forRoom roomJID: String) {
        unreadCounts[roomJID] = 0
        lastReadTimestamps[roomJID] = Date()
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
    }
    
    public func resetAll() {
        unreadCounts.removeAll()
        lastReadTimestamps.removeAll()
    }
}
