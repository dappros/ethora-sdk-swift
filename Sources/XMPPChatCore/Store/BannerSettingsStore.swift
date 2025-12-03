//
//  BannerSettingsStore.swift
//  XMPPChatCore
//
//  Store for managing off-clinic hours banner settings
//

import Foundation
import Combine

@MainActor
public class BannerSettingsStore: ObservableObject {
    public static let shared = BannerSettingsStore()
    
    @Published public var settings: BannerSettings {
        didSet {
            saveSettings()
        }
    }
    
    private let settingsKey = "ethora_banner_settings"
    
    private init() {
        // Load settings from UserDefaults
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(BannerSettings.self, from: data) {
            self.settings = decoded
        } else {
            // Default settings
            self.settings = BannerSettings()
        }
    }
    
    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }
    
    /// Update banner settings
    public func updateSettings(
        isEnabled: Bool? = nil,
        startHour: Int? = nil,
        endHour: Int? = nil,
        bannerText: String? = nil
    ) {
        var updated = settings
        
        if let isEnabled = isEnabled {
            updated.isEnabled = isEnabled
        }
        if let startHour = startHour {
            updated.startHour = max(0, min(23, startHour)) // Clamp to 0-23
        }
        if let endHour = endHour {
            updated.endHour = max(0, min(23, endHour)) // Clamp to 0-23
        }
        if let bannerText = bannerText {
            updated.bannerText = bannerText
        }
        
        settings = updated
    }
}

