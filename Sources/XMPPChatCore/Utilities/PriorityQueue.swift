//
//  PriorityQueue.swift
//  XMPPChatCore
//
//  Priority queue implementation
//

import Foundation

public struct PriorityQueue<T> {
    private var heap: [QueueItem<T>] = []
    private let comparator: (T, T) -> Bool
    
    public init(comparator: @escaping (T, T) -> Bool) {
        self.comparator = comparator
    }
    
    public var isEmpty: Bool {
        return heap.isEmpty
    }
    
    public var count: Int {
        return heap.count
    }
    
    public mutating func enqueue(_ item: T, priority: Int) {
        let queueItem = QueueItem(item: item, priority: priority)
        heap.append(queueItem)
        siftUp(heap.count - 1)
    }
    
    public mutating func dequeue() -> T? {
        guard !heap.isEmpty else { return nil }
        
        if heap.count == 1 {
            return heap.removeFirst().item
        }
        
        let top = heap[0]
        heap[0] = heap.removeLast()
        siftDown(0)
        
        return top.item
    }
    
    public func peek() -> T? {
        return heap.first?.item
    }
    
    private mutating func siftUp(_ index: Int) {
        var child = index
        var parent = (child - 1) / 2
        
        while child > 0 && heap[child].priority > heap[parent].priority {
            heap.swapAt(child, parent)
            child = parent
            parent = (child - 1) / 2
        }
    }
    
    private mutating func siftDown(_ index: Int) {
        var parent = index
        
        while true {
            let leftChild = 2 * parent + 1
            let rightChild = 2 * parent + 2
            var candidate = parent
            
            if leftChild < heap.count && heap[leftChild].priority > heap[candidate].priority {
                candidate = leftChild
            }
            
            if rightChild < heap.count && heap[rightChild].priority > heap[candidate].priority {
                candidate = rightChild
            }
            
            if candidate == parent {
                return
            }
            
            heap.swapAt(parent, candidate)
            parent = candidate
        }
    }
}

private struct QueueItem<T> {
    let item: T
    let priority: Int
}
