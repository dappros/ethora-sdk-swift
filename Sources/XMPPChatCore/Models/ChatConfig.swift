//
//  ChatConfig.swift
//  XMPPChatCore
//
//  Configuration model mirroring IConfig from web component
//

import Foundation
import SwiftUI

// MARK: - Main Chat Config

public struct ChatConfig {
    public var appId: String?

    // Basic UI Settings
    public var disableHeader: Bool?
    public var disableMedia: Bool?
    public var colors: ChatColors?
    
    // Login Configurations
    public var googleLogin: GoogleLoginConfig?
    public var jwtLogin: JWTLoginConfig?
    public var userLogin: UserLoginConfig?
    public var customLogin: CustomLoginConfig?
    
    // API & XMPP Settings
    public var baseUrl: String?
    public var customAppToken: String?
    public var xmppSettings: XMPPSettings?
    
    // Room Settings
    public var disableRooms: Bool?
    public var defaultLogin: Bool?
    public var disableInteractions: Bool?
    public var chatHeaderBurgerMenu: Bool?
    public var forceSetRoom: Bool?
    public var setRoomJidInPath: Bool?
    public var disableRoomMenu: Bool?
    public var disableRoomConfig: Bool?
    public var disableNewChatButton: Bool?
    
    // Styling
    public var roomListStyles: [String: Any]?
    public var chatRoomStyles: [String: Any]?
    public var backgroundChat: BackgroundChatConfig?
    public var bubleMessage: MessageBubbleStyle?
    
    // Header
    public var headerLogo: String?
    public var headerMenu: (() -> Void)?
    public var headerChatMenu: (() -> Void)?
    
    // Rooms
    public var defaultRooms: [Room]?
    public var customRooms: CustomRoomsConfig?
    
    // Tokens & Auth
    public var refreshTokens: RefreshTokensConfig?
    
    // Translations
    public var translates: TranslationsConfig?
    
    // Features
    public var disableProfilesInteractions: Bool?
    public var disableUserCount: Bool?
    public var clearStoreBeforeInit: Bool?
    public var disableSentLogic: Bool?
    public var initBeforeLoad: Bool?
    public var newArch: Bool?
    public var qrUrl: String?
    
    // Secondary Send Button
    public var secondarySendButton: SecondarySendButtonConfig?
    
    // Retry
    public var enableRoomsRetry: EnableRoomsRetryConfig?
    
    // Chat Header Additional
    public var chatHeaderAdditional: (enabled: Bool, element: AnyView)?
    
    // Bot & Messages
    public var botMessageAutoScroll: Bool?
    public var messageTextFilter: MessageTextFilterConfig?
    public var whitelistSystemMessage: [String]?
    
    // Typing Indicator
    public var disableTypingIndicator: Bool?
    public var customTypingIndicator: CustomTypingIndicatorConfig?
    
    // Block Message Sending
    public var blockMessageSendingWhenProcessing: BlockMessageSendingConfig?
    
    // Chat Info
    public var disableChatInfo: DisableChatInfoConfig?
    public var chatHeaderSettings: ChatHeaderSettingsConfig?
    
    // Store
    public var useStoreConsoleEnabled: Bool?
    
    // Notifications
    public var messageNotifications: MessageNotificationConfig?
    public var push: PushNotificationConfig?
    
    // Event Handlers
    public var eventHandlers: ChatEventHandlers?
    
    // Custom Components
    public var customComponents: CustomComponentsProtocol?
    
    public init() {
        // Default initialization
    }
}

// MARK: - Color Extension

public extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
