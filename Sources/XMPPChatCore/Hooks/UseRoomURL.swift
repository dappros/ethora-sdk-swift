//
//  UseRoomURL.swift
//  XMPPChatCore
//
//  Room URL management
//

import Foundation

#if os(iOS)
import UIKit
#endif

public class RoomURLManager {
    public static let shared = RoomURLManager()
    
    private init() {}
    
    private var currentRoomJID: String?
    
    public func setRoomJIDInPath(_ roomJID: String) {
        currentRoomJID = roomJID
        #if os(iOS)
        // In iOS, we can't directly modify the URL in the same way as web
        // This would need to be handled by the app's navigation system
        // For now, we just store it
        #endif
    }
    
    public func getRoomJIDFromPath() -> String? {
        return currentRoomJID
    }
    
    public func clearRoomJIDFromPath() {
        currentRoomJID = nil
    }
}
