//
//  ActionLogger.swift
//  XMPPChatCore
//
//  Action logger middleware
//

import Foundation
import Combine

public class ActionLogger {
    private var logs: [ActionLogEntry] = []
    private let maxLogs: Int = 1000
    public var isEnabled: Bool = true
    
    public init() {}
    
    public func log(_ action: Any, state: Any?) {
        guard isEnabled else { return }
        
        let entry = ActionLogEntry(
            timestamp: Date(),
            action: String(describing: action),
            state: state != nil ? String(describing: state) : nil
        )
        
        logs.append(entry)
        
        if logs.count > maxLogs {
            logs.removeFirst()
        }
    }
    
    public func getLogs() -> [ActionLogEntry] {
        return logs
    }
    
    public func clearLogs() {
        logs.removeAll()
    }
}

public struct ActionLogEntry {
    public let timestamp: Date
    public let action: String
    public let state: String?
}

public func actionLoggerMiddleware(
    logger: ActionLogger
) -> (@escaping (Any) -> Void) -> (Any) -> Void {
    return { next in
        return { action in
            logger.log(action, state: nil)
            next(action)
        }
    }
}
