//
//  UsePrevious.swift
//  XMPPChatCore
//
//  Track previous value hook
//

import Foundation
import Combine

@propertyWrapper
public struct UsePrevious<T: Equatable> {
    private var current: T
    private var previous: T?
    
    public var wrappedValue: T {
        get { current }
        set {
            if newValue != current {
                previous = current
                current = newValue
            }
        }
    }
    
    public var projectedValue: T? {
        return previous
    }
    
    public init(wrappedValue: T) {
        self.current = wrappedValue
        self.previous = nil
    }
}

public func usePrevious<T: Equatable>(_ value: T) -> T? {
    // Swift doesn't have hooks like React, but we can use a property wrapper
    // For functional approach, use a view model or observable object
    return nil // Placeholder - actual implementation depends on context
}
