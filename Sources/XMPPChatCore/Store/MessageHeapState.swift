//
//  MessageHeapState.swift
//  XMPPChatCore
//
//  Message heap state management
//

import Foundation
import Combine

@MainActor
public class MessageHeapState: ObservableObject {
    @Published public var heap: [String: [Message]] = [:] // roomJID: [messages]
    @Published public var heapComplete: [String: Bool] = [:] // roomJID: isComplete
    
    private let storage = LocalStorage.shared
    
    public init() {
        loadFromStorage()
    }
    
    public func addMessages(_ messages: [Message], forRoom roomJID: String) {
        if heap[roomJID] == nil {
            heap[roomJID] = []
        }
        heap[roomJID]?.append(contentsOf: messages)
        saveToStorage()
    }
    
    public func setMessages(_ messages: [Message], forRoom roomJID: String) {
        heap[roomJID] = messages
        saveToStorage()
    }
    
    public func getMessages(forRoom roomJID: String) -> [Message] {
        return heap[roomJID] ?? []
    }
    
    public func markComplete(forRoom roomJID: String) {
        heapComplete[roomJID] = true
        saveToStorage()
    }
    
    public func isComplete(forRoom roomJID: String) -> Bool {
        return heapComplete[roomJID] ?? false
    }
    
    public func clear(forRoom roomJID: String) {
        heap.removeValue(forKey: roomJID)
        heapComplete.removeValue(forKey: roomJID)
        saveToStorage()
    }
    
    public func clearAll() {
        heap.removeAll()
        heapComplete.removeAll()
        saveToStorage()
    }
    
    private func saveToStorage() {
        // Save heap state to local storage
        // Implementation depends on storage mechanism
    }
    
    private func loadFromStorage() {
        // Load heap state from local storage
        // Implementation depends on storage mechanism
    }
}
