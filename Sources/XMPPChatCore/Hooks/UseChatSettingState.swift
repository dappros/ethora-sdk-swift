//
//  UseChatSettingState.swift
//  XMPPChatCore
//
//  Chat settings state management
//

import Foundation
import Combine

@MainActor
public class ChatSettingState: ObservableObject {
    @Published public var settings: ChatSettings = ChatSettings()
    
    private let storage = LocalStorage.shared
    private let settingsKey = "chat_settings"
    
    public init() {
        loadSettings()
    }
    
    public func updateSettings(_ newSettings: ChatSettings) {
        settings = newSettings
        saveSettings()
    }
    
    public func updateSetting<T>(_ keyPath: WritableKeyPath<ChatSettings, T>, value: T) {
        settings[keyPath: keyPath] = value
        saveSettings()
    }
    
    private func saveSettings() {
        storage.set(settings, forKey: settingsKey)
    }
    
    private func loadSettings() {
        if let loaded = storage.get(ChatSettings.self, forKey: settingsKey) {
            settings = loaded
        }
    }
}

public struct ChatSettings: Codable {
    public var notificationsEnabled: Bool = true
    public var soundEnabled: Bool = true
    public var showReadReceipts: Bool = true
    public var showTypingIndicator: Bool = true
    public var theme: String = "light"
    
    public init() {}
}
