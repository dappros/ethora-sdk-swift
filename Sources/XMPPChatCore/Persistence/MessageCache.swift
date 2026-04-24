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
    private let cacheIndexKey = "XMPPChat_Messages_Index"
    
    // MARK: - Configuration (hybrid per-room + global limits)
    
    // Cache up to N messages per room (matches web limit by default)
    private var maxCachedMessagesPerRoom: Int = 100
    
    // Global limits across all rooms
    private var maxCachedRooms: Int = 50
    private var maxTotalCachedMessages: Int = 5_000
    
    // Optional TTL in days for cached messages (nil = disabled)
    private var maxMessageAgeDays: Int? = nil
    
    // Lightweight per-room metadata used for global eviction
    private struct CachedRoomMeta: Codable {
        let roomJID: String
        var lastAccessTimestamp: TimeInterval
        var lastMessageTimestamp: Int64?
        var messageCount: Int
    }
    
    private init() {}
    
    // MARK: - Public configuration
    
    /// Configure cache limits.
    ///
    /// - Parameters:
    ///   - maxRooms: Maximum number of rooms to keep cached (default: 50).
    ///   - maxMessagesPerRoom: Maximum number of messages per room (default: 50).
    ///   - maxTotalMessages: Maximum total number of cached messages across all rooms (default: 5_000).
    ///   - maxAgeDays: Optional TTL in days; messages older than this are pruned from cache (default: nil – disabled).
    ///
    /// Recommended defaults for typical devices are the built-in values above.
    /// Hosts can call this early in app startup to tighten or relax limits.
    public func configure(
        maxRooms: Int? = nil,
        maxMessagesPerRoom: Int? = nil,
        maxTotalMessages: Int? = nil,
        maxAgeDays: Int? = nil
    ) {
        if let maxRooms {
            self.maxCachedRooms = max(1, maxRooms)
        }
        if let maxMessagesPerRoom {
            self.maxCachedMessagesPerRoom = max(1, maxMessagesPerRoom)
        }
        if let maxTotalMessages {
            self.maxTotalCachedMessages = max(1, maxTotalMessages)
        }
        // maxAgeDays: allow nil (disabled) or positive values
        self.maxMessageAgeDays = maxAgeDays
    }
    
    // MARK: - Index helpers
    
    private func loadIndex() -> [String: CachedRoomMeta] {
        guard let data = UserDefaults.standard.data(forKey: cacheIndexKey) else {
            return [:]
        }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode([String: CachedRoomMeta].self, from: data)
        } catch {
            // If index is corrupted, clear it and start fresh
            UserDefaults.standard.removeObject(forKey: cacheIndexKey)
            return [:]
        }
    }
    
    private func saveIndex(_ index: [String: CachedRoomMeta]) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(index)
            UserDefaults.standard.set(data, forKey: cacheIndexKey)
        } catch {
            // If index cannot be saved, fail silently – core caching still works per room
        }
    }
    
    /// Mark a room as accessed without modifying its cached messages.
    /// This is used to keep LRU ordering in sync with UI activity.
    public func markRoomAccessed(roomJID: String) {
        var index = loadIndex()
        let now = Date().timeIntervalSince1970
        
        if var meta = index[roomJID] {
            meta.lastAccessTimestamp = now
            index[roomJID] = meta
        } else {
            // If we don't have metadata yet but room has cached messages, approximate count from stored data
            let key = cacheKeyPrefix + roomJID
            let messageCount: Int
            if let data = UserDefaults.standard.data(forKey: key) {
                do {
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let messages = try decoder.decode([Message].self, from: data)
                    messageCount = messages.count
                } catch {
                    messageCount = 0
                }
            } else {
                messageCount = 0
            }
            
            let meta = CachedRoomMeta(
                roomJID: roomJID,
                lastAccessTimestamp: now,
                lastMessageTimestamp: nil,
                messageCount: messageCount
            )
            index[roomJID] = meta
        }
        
        saveIndex(index)
    }
    
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
            
            // Update global index metadata for this room
            var index = loadIndex()
            let now = Date().timeIntervalSince1970
            let lastTimestamp = messagesToCache.last?.timestamp
            let meta = CachedRoomMeta(
                roomJID: roomJID,
                lastAccessTimestamp: now,
                lastMessageTimestamp: lastTimestamp,
                messageCount: messagesToCache.count
            )
            index[roomJID] = meta
            saveIndex(index)
            
            //print("💾 MessageCache: Saved \(messagesToCache.count) messages for room: \(roomJID)")
        } catch {
            //print("❌ MessageCache: Failed to save messages for room \(roomJID): \(error)")
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
            
            // Update access metadata for LRU ordering
            var index = loadIndex()
            let now = Date().timeIntervalSince1970
            let lastTimestamp = messages.last?.timestamp
            let meta = CachedRoomMeta(
                roomJID: roomJID,
                lastAccessTimestamp: now,
                lastMessageTimestamp: lastTimestamp,
                messageCount: messages.count
            )
            index[roomJID] = meta
            saveIndex(index)
            
            //print("📂 MessageCache: Loaded \(messages.count) cached messages for room: \(roomJID)")
            return messages
        } catch {
            //print("❌ MessageCache: Failed to load messages for room \(roomJID): \(error)")
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
        
        // Remove room from global index as well
        var index = loadIndex()
        index.removeValue(forKey: roomJID)
        saveIndex(index)
        
        //print("🗑️ MessageCache: Cleared cached messages for room: \(roomJID)")
    }
    
    /// Clear all cached messages (useful for logout)
    public func clearAll() {
        let keys = UserDefaults.standard.dictionaryRepresentation().keys
        for key in keys {
            if key.hasPrefix(cacheKeyPrefix) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        
        // Clear global index as well
        UserDefaults.standard.removeObject(forKey: cacheIndexKey)
        
        //print("🗑️ MessageCache: Cleared all cached messages")
    }
    
    /// Check if there are cached messages for a room
    public func hasCachedMessages(forRoomJID roomJID: String) -> Bool {
        let key = cacheKeyPrefix + roomJID
        return UserDefaults.standard.data(forKey: key) != nil
    }
    
    // MARK: - Eviction / cleanup
    
    /// Run hybrid cleanup:
    /// - Always applies TTL pruning if configured.
    /// - Applies global LRU-based eviction when global limits are exceeded.
    public func cleanupIfNeeded() {
        var index = loadIndex()
        if index.isEmpty {
            return
        }
        
        let now = Date().timeIntervalSince1970
        var totalRooms = index.count
        var totalMessages = index.values.reduce(0) { $0 + $1.messageCount }
        var indexChanged = false
        
        // 1) TTL pruning: remove rooms whose last message is older than maxMessageAgeDays
        if let maxAgeDays = maxMessageAgeDays, maxAgeDays > 0 {
            let maxAgeSeconds = TimeInterval(maxAgeDays * 24 * 60 * 60)
            // lastMessageTimestamp is in milliseconds since epoch
            let cutoffMillis = Int64((now - maxAgeSeconds) * 1000)
            
            for (roomJID, meta) in index {
                if let lastTs = meta.lastMessageTimestamp, lastTs < cutoffMillis {
                    clearMessages(forRoomJID: roomJID)
                    totalRooms -= 1
                    totalMessages -= meta.messageCount
                    indexChanged = true
                }
            }
            
            if indexChanged {
                index = loadIndex()
            }
        }
        
        if index.isEmpty {
            return
        }
        
        totalRooms = index.count
        totalMessages = index.values.reduce(0) { $0 + $1.messageCount }
        
        // 2) Global LRU-based eviction when over limits
        if totalRooms > maxCachedRooms || totalMessages > maxTotalCachedMessages {
            // Sort rooms by lastAccessTimestamp ascending (least recently used first)
            let sortedMetas = index.values.sorted { $0.lastAccessTimestamp < $1.lastAccessTimestamp }
            
            var mutableIndex = index
            for meta in sortedMetas {
                if totalRooms <= maxCachedRooms && totalMessages <= maxTotalCachedMessages {
                    break
                }
                
                clearMessages(forRoomJID: meta.roomJID)
                mutableIndex.removeValue(forKey: meta.roomJID)
                totalRooms -= 1
                totalMessages -= meta.messageCount
                indexChanged = true
            }
            
            if indexChanged {
                saveIndex(mutableIndex)
            }
        }
    }
    
    /// Aggressive cleanup entry point – currently just delegates to cleanupIfNeeded.
    /// Can be extended later for more forceful strategies if needed.
    public func cleanupAll() {
        cleanupIfNeeded()
    }
}
