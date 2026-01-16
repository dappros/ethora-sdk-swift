//
//  MessageQueueManager.swift
//  XMPPChatCore
//
//  Message queue and retry manager
//

import Foundation
import Combine
import XMPPChatCore

@MainActor
public class MessageQueueManager: ObservableObject {
    @Published public var failedMessages: [QueuedMessage] = []
    @Published public var pendingMessages: [QueuedMessage] = []
    
    private var retryTimer: Timer?
    private let maxRetries: Int = 3
    private let retryDelay: TimeInterval = 5.0
    
    public init() {
        startRetryTimer()
    }
    
    public func addMessage(_ message: Message, sendFunction: @escaping () async throws -> Void) {
        let queuedMessage = QueuedMessage(
            message: message,
            sendFunction: sendFunction,
            retryCount: 0
        )
        pendingMessages.append(queuedMessage)
        
        Task {
            await trySendMessage(queuedMessage)
        }
    }
    
    public func markAsFailed(_ message: Message) {
        if let index = pendingMessages.firstIndex(where: { $0.message.id == message.id }) {
            let queued = pendingMessages[index]
            pendingMessages.remove(at: index)
            
            if queued.retryCount < maxRetries {
                var updated = queued
                updated.retryCount += 1
                failedMessages.append(updated)
            }
        }
    }
    
    public func retryMessage(_ queuedMessage: QueuedMessage) {
        if let index = failedMessages.firstIndex(where: { $0.message.id == queuedMessage.message.id }) {
            failedMessages.remove(at: index)
            pendingMessages.append(queuedMessage)
            
            Task {
                await trySendMessage(queuedMessage)
            }
        }
    }
    
    public func removeMessage(_ messageId: String) {
        pendingMessages.removeAll { $0.message.id == messageId }
        failedMessages.removeAll { $0.message.id == messageId }
    }
    
    private func trySendMessage(_ queuedMessage: QueuedMessage) async {
        do {
            try await queuedMessage.sendFunction()
            removeMessage(queuedMessage.message.id)
        } catch {
            markAsFailed(queuedMessage.message)
        }
    }
    
    private func startRetryTimer() {
        retryTimer = Timer.scheduledTimer(withTimeInterval: retryDelay, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.retryFailedMessages()
            }
        }
    }
    
    private func retryFailedMessages() {
        let toRetry = failedMessages.filter { $0.retryCount < maxRetries }
        for message in toRetry {
            retryMessage(message)
        }
    }
    
    deinit {
        retryTimer?.invalidate()
    }
}

public struct QueuedMessage: Identifiable {
    public let id: String
    public let message: Message
    public let sendFunction: () async throws -> Void
    public var retryCount: Int
    
    public init(
        message: Message,
        sendFunction: @escaping () async throws -> Void,
        retryCount: Int = 0
    ) {
        self.id = message.id
        self.message = message
        self.sendFunction = sendFunction
        self.retryCount = retryCount
    }
}
