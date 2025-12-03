//
//  BannerSettings.swift
//  XMPPChatCore
//
//  Settings for off-clinic hours banner
//

import Foundation

public struct BannerSettings: Codable, Equatable {
    public var isEnabled: Bool
    public var startHour: Int  // 0-23
    public var endHour: Int     // 0-23
    public var bannerText: String
    
    public init(
        isEnabled: Bool = false,
        startHour: Int = 21,
        endHour: Int = 7,
        bannerText: String = "off-clinic hours"
    ) {
        self.isEnabled = isEnabled
        self.startHour = startHour
        self.endHour = endHour
        self.bannerText = bannerText
    }
    
    /// Check if current time is within the off-clinic hours range
    public func isCurrentlyActive() -> Bool {
        guard isEnabled else { return false }
        
        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        
        // Handle case where endHour < startHour (e.g., 21:00 to 7:00)
        if endHour < startHour {
            // Active if currentHour >= startHour OR currentHour < endHour
            return currentHour >= startHour || currentHour < endHour
        } else {
            // Active if currentHour >= startHour AND currentHour < endHour
            return currentHour >= startHour && currentHour < endHour
        }
    }
}

