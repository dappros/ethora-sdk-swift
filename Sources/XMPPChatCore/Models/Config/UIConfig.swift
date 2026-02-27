//
//  UIConfig.swift
//  XMPPChatCore
//

import Foundation
import SwiftUI

public struct ChatColors: Codable, Equatable {
    public let primary: String
    public let secondary: String
    
    public init(primary: String, secondary: String) {
        self.primary = primary
        self.secondary = secondary
    }
    
    public var primaryColor: Color {
        Color(hex: primary)
    }
    
    public var secondaryColor: Color {
        Color(hex: secondary)
    }
}

public struct BackgroundChatConfig: Codable, Equatable {
    public let color: String?
    public let image: String?
    
    public init(color: String? = nil, image: String? = nil) {
        self.color = color
        self.image = image
    }
}

public struct MessageBubbleStyle: Codable, Equatable {
    public let backgroundMessageUser: String?
    public let backgroundMessage: String?
    public let colorUser: String?
    public let color: String?
    public let borderRadius: Double?
    
    public init(
        backgroundMessageUser: String? = nil,
        backgroundMessage: String? = nil,
        colorUser: String? = nil,
        color: String? = nil,
        borderRadius: Double? = nil
    ) {
        self.backgroundMessageUser = backgroundMessageUser
        self.backgroundMessage = backgroundMessage
        self.colorUser = colorUser
        self.color = color
        self.borderRadius = borderRadius
    }
}
