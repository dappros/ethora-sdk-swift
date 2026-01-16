//
//  UseComposing.swift
//  XMPPChatCore
//
//  Advanced composing state
//

import Foundation
import Combine

@MainActor
public class ComposingManager: ObservableObject {
    @Published public var composingUsers: [String: [String]] = [:] // roomJID: [userIds]
    @Published public var composingTimeouts: [String: Timer] = [:]
    
    private let timeoutInterval: TimeInterval = 3.0
    
    public func startComposing(userId: String, roomJID: String) {
        if composingUsers[roomJID] == nil {
            composingUsers[roomJID] = []
        }
        
        if !composingUsers[roomJID]!.contains(userId) {
            composingUsers[roomJID]!.append(userId)
        }
        
        // Reset timeout
        composingTimeouts["\(roomJID)-\(userId)"]?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: timeoutInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.stopComposing(userId: userId, roomJID: roomJID)
            }
        }
        composingTimeouts["\(roomJID)-\(userId)"] = timer
    }
    
    public func stopComposing(userId: String, roomJID: String) {
        composingUsers[roomJID]?.removeAll { $0 == userId }
        composingTimeouts["\(roomJID)-\(userId)"]?.invalidate()
        composingTimeouts.removeValue(forKey: "\(roomJID)-\(userId)")
    }
    
    public func getComposingUsers(forRoom roomJID: String) -> [String] {
        return composingUsers[roomJID] ?? []
    }
    
    public func clear(forRoom roomJID: String) {
        composingUsers.removeValue(forKey: roomJID)
        composingTimeouts.filter { $0.key.hasPrefix(roomJID) }.forEach { $0.value.invalidate() }
        composingTimeouts = composingTimeouts.filter { !$0.key.hasPrefix(roomJID) }
    }
}
