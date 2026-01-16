//
//  UseMessageLoaderQueue.swift
//  XMPPChatCore
//
//  Message loading queue
//

import Foundation

@MainActor
public class MessageLoaderQueueHook: ObservableObject {
    @Published public var loadingRooms: Set<String> = []
    
    private var queue = PriorityQueue<String>(comparator: { _, _ in true })
    private var isLoading: Bool = false
    
    public func enqueueLoadMessages(
        roomJID: String,
        max: Int,
        beforeMessageId: String?,
        loadFunction: @escaping (String, Int, String?) async throws -> Void
    ) {
        queue.enqueue(roomJID, priority: loadingRooms.contains(roomJID) ? 0 : 1)
        
        if !isLoading {
            processQueue(loadFunction: loadFunction)
        }
    }
    
    private func processQueue(
        loadFunction: @escaping (String, Int, String?) async throws -> Void
    ) {
        guard !isLoading, let roomJID = queue.dequeue() else {
            isLoading = false
            return
        }
        
        isLoading = true
        loadingRooms.insert(roomJID)
        
        Task {
            do {
                try await loadFunction(roomJID, 50, nil) // Default max
                await MainActor.run {
                    loadingRooms.remove(roomJID)
                    isLoading = false
                    processQueue(loadFunction: loadFunction)
                }
            } catch {
                await MainActor.run {
                    loadingRooms.remove(roomJID)
                    isLoading = false
                    processQueue(loadFunction: loadFunction)
                }
            }
        }
    }
}
