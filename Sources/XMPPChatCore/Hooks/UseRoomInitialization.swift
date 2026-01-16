//
//  UseRoomInitialization.swift
//  XMPPChatCore
//
//  Room initialization hooks
//

import Foundation
import Combine

@MainActor
public class RoomInitializationManager: ObservableObject {
    @Published public var initializedRooms: Set<String> = []
    @Published public var initializingRooms: Set<String> = []
    
    public func initializeRoom(_ roomJID: String, client: XMPPClient) async throws {
        guard !initializedRooms.contains(roomJID) && !initializingRooms.contains(roomJID) else {
            return
        }
        
        initializingRooms.insert(roomJID)
        defer {
            initializingRooms.remove(roomJID)
        }
        
        // Join room - send presence to room
        // This is handled by the room operations, but for initialization we just mark as initialized
        // The actual join happens when the room is opened
        
        // Load initial messages
        // This would be handled by the room store
        
        initializedRooms.insert(roomJID)
    }
    
    public func isInitialized(_ roomJID: String) -> Bool {
        return initializedRooms.contains(roomJID)
    }
    
    public func reset() {
        initializedRooms.removeAll()
        initializingRooms.removeAll()
    }
}
