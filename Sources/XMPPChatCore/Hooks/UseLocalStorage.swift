//
//  UseLocalStorage.swift
//  XMPPChatCore
//
//  Local storage utilities
//

import Foundation

public class LocalStorage {
    public static let shared = LocalStorage()
    
    private let userDefaults = UserDefaults.standard
    
    private init() {}
    
    public func set<T: Codable>(_ value: T, forKey key: String) {
        if let encoded = try? JSONEncoder().encode(value) {
            userDefaults.set(encoded, forKey: key)
        }
    }
    
    public func get<T: Codable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    
    public func remove(forKey key: String) {
        userDefaults.removeObject(forKey: key)
    }
    
    public func clear() {
        if let bundleID = Bundle.main.bundleIdentifier {
            userDefaults.removePersistentDomain(forName: bundleID)
        }
    }
}
