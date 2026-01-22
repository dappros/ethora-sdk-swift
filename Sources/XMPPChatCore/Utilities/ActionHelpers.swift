//
//  ActionHelpers.swift
//  XMPPChatCore
//
//  Action validation and helpers
//

import Foundation

public protocol Action {
    var type: String { get }
}

public func isValidAction(_ action: Any) -> Bool {
    if let action = action as? Action {
        return !action.type.isEmpty
    }
    return false
}

public func createSafeDispatch(_ dispatch: @escaping (Any) -> Void) -> (Any) -> Void {
    return { action in
        if isValidAction(action) {
            dispatch(action)
        } else {
            //print("Warning: Invalid action dispatched: \(action)")
        }
    }
}

public func createAsyncAction<T>(
    _ actionType: String,
    payload: T,
    asyncFunction: @escaping () async throws -> Void
) async throws {
    try await asyncFunction()
}
