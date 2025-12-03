//
//  MessageCache.swift
//  XMPPChatCore
//
//  Caches messages per room for persistence across app restarts
//

import Foundation

@MainActor
public class MessageCache {
    public static let shared = MessageCache()
    
    private let cacheKeyPrefix = "XMPPChat_Messages_"
    private let maxCachedMessagesPerRoom = 100 // Cache up to 100 messages per room
    
    private init() {}
    
    /// Save messages for a room
    public func saveMessages(_ messages: [Message], forRoomJID roomJID: String) {
        // Limit to most recent messages
        let messagesToCache = Array(messages.suffix(maxCachedMessagesPerRoom))
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(messagesToCache)
            
            let key = cacheKeyPrefix + roomJID
            UserDefaults.standard.set(data, forKey: key)
            
            // Also save the timestamp of the last message for sorting
            if let lastMessage = messagesToCache.last,
               let timestamp = lastMessage.timestamp {
                let timestampKey = cacheKeyPrefix + roomJID + "_timestamp"
                UserDefaults.standard.set(timestamp, forKey: timestampKey)
            }
            
            print("💾 MessageCache: Saved \(messagesToCache.count) messages for room: \(roomJID)")
        } catch {
            print("❌ MessageCache: Failed to save messages for room \(roomJID): \(error)")
        }
    }
    
    /// Load cached messages for a room
    public func loadMessages(forRoomJID roomJID: String) -> [Message]? {
        let key = cacheKeyPrefix + roomJID
        
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let messages = try decoder.decode([Message].self, from: data)
            
            print("📂 MessageCache: Loaded \(messages.count) cached messages for room: \(roomJID)")
            return messages
        } catch {
            print("❌ MessageCache: Failed to load messages for room \(roomJID): \(error)")
            return nil
        }
    }
    
    /// Get cached timestamp for a room (for sorting)
    public func getCachedTimestamp(forRoomJID roomJID: String) -> Int64? {
        let timestampKey = cacheKeyPrefix + roomJID + "_timestamp"
        return UserDefaults.standard.object(forKey: timestampKey) as? Int64
    }
    
    /// Clear cached messages for a room
    public func clearMessages(forRoomJID roomJID: String) {
        let key = cacheKeyPrefix + roomJID
        let timestampKey = cacheKeyPrefix + roomJID + "_timestamp"
        
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: timestampKey)
        
        print("🗑️ MessageCache: Cleared cached messages for room: \(roomJID)")
    }
    
    /// Clear all cached messages (useful for logout)
    public func clearAll() {
        let keys = UserDefaults.standard.dictionaryRepresentation().keys
        for key in keys {
            if key.hasPrefix(cacheKeyPrefix) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        print("🗑️ MessageCache: Cleared all cached messages")
    }
    
    /// Check if there are cached messages for a room
    public func hasCachedMessages(forRoomJID roomJID: String) -> Bool {
        let key = cacheKeyPrefix + roomJID
        return UserDefaults.standard.data(forKey: key) != nil
    }
}

