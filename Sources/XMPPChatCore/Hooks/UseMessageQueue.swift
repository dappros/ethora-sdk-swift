//
//  UseMessageQueue.swift
//  XMPPChatCore
//
//  Message queue management
//

import Foundation
import Combine

@MainActor
public class MessageQueueHook: ObservableObject {
    @Published public var queue: [QueuedMessageItem] = []
    
    public func enqueue(_ message: Message, priority: Int = 0) {
        let item = QueuedMessageItem(message: message, priority: priority, timestamp: Date())
        queue.append(item)
        queue.sort { $0.priority > $1.priority }
    }
    
    public func dequeue() -> Message? {
        guard !queue.isEmpty else { return nil }
        return queue.removeFirst().message
    }
    
    public func remove(_ messageId: String) {
        queue.removeAll { $0.message.id == messageId }
    }
    
    public func clear() {
        queue.removeAll()
    }
    
    public var isEmpty: Bool {
        return queue.isEmpty
    }
}

public struct QueuedMessageItem: Identifiable {
    public let id: String
    public let message: Message
    public let priority: Int
    public let timestamp: Date
    
    public init(message: Message, priority: Int, timestamp: Date) {
        self.id = message.id
        self.message = message
        self.priority = priority
        self.timestamp = timestamp
    }
}
