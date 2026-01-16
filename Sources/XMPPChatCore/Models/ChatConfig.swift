//
//  ChatConfig.swift
//  XMPPChatCore
//
//  Configuration model mirroring IConfig from web component
//

import Foundation
import SwiftUI

// MARK: - Firebase Config

public struct FirebaseConfig: Codable, Equatable {
    public let apiKey: String
    public let authDomain: String
    public let projectId: String
    public let storageBucket: String
    public let messagingSenderId: String
    public let appId: String
    
    public init(
        apiKey: String,
        authDomain: String,
        projectId: String,
        storageBucket: String,
        messagingSenderId: String,
        appId: String
    ) {
        self.apiKey = apiKey
        self.authDomain = authDomain
        self.projectId = projectId
        self.storageBucket = storageBucket
        self.messagingSenderId = messagingSenderId
        self.appId = appId
    }
}

// MARK: - Login Configurations

public struct GoogleLoginConfig: Codable, Equatable {
    public let enabled: Bool
    public let firebaseConfig: FirebaseConfig
    
    public init(enabled: Bool, firebaseConfig: FirebaseConfig) {
        self.enabled = enabled
        self.firebaseConfig = firebaseConfig
    }
}

public struct JWTLoginConfig: Codable, Equatable {
    public let token: String
    public let enabled: Bool
    
    public init(token: String, enabled: Bool) {
        self.token = token
        self.enabled = enabled
    }
}

public struct UserLoginConfig: Codable, Equatable {
    public let enabled: Bool
    public let user: User?
    
    public init(enabled: Bool, user: User?) {
        self.enabled = enabled
        self.user = user
    }
}

public struct CustomLoginConfig {
    public let enabled: Bool
    public let loginFunction: () async throws -> User?
    
    public init(enabled: Bool, loginFunction: @escaping () async throws -> User?) {
        self.enabled = enabled
        self.loginFunction = loginFunction
    }
}

// MARK: - Colors

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

// MARK: - Refresh Tokens

public struct RefreshTokensConfig {
    public let enabled: Bool
    public let refreshFunction: (() async throws -> (accessToken: String, refreshToken: String?))?
    
    public init(
        enabled: Bool,
        refreshFunction: (() async throws -> (accessToken: String, refreshToken: String?))? = nil
    ) {
        self.enabled = enabled
        self.refreshFunction = refreshFunction
    }
}

// MARK: - Background Chat

public struct BackgroundChatConfig: Codable, Equatable {
    public let color: String?
    public let image: String?
    
    public init(color: String? = nil, image: String? = nil) {
        self.color = color
        self.image = image
    }
}

// MARK: - Message Bubble Styling

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

// MARK: - Custom Rooms

public struct CustomRoomsConfig {
    public let rooms: [Room]
    public let disableGetRooms: Bool
    public let singleRoom: Bool
    
    public init(rooms: [Room], disableGetRooms: Bool = false, singleRoom: Bool = false) {
        self.rooms = rooms
        self.disableGetRooms = disableGetRooms
        self.singleRoom = singleRoom
    }
}

// MARK: - Translations

public enum Iso639_1Code: String, Codable {
    case en = "en"
    case es = "es"
    case pt = "pt"
    case ht = "ht"
    case zh = "zh"
}

public struct TranslationsConfig: Codable, Equatable {
    public let enabled: Bool
    public let translations: Iso639_1Code?
    
    public init(enabled: Bool, translations: Iso639_1Code? = nil) {
        self.enabled = enabled
        self.translations = translations
    }
}

// MARK: - Secondary Send Button

public struct SecondarySendButtonConfig {
    public let enabled: Bool
    public let messageEdit: String
    public let label: AnyView?
    public let buttonStyles: [String: Any]?
    public let hideInputSendButton: Bool
    public let overwriteEnterClick: Bool
    
    public init(
        enabled: Bool,
        messageEdit: String,
        label: AnyView? = nil,
        buttonStyles: [String: Any]? = nil,
        hideInputSendButton: Bool = false,
        overwriteEnterClick: Bool = false
    ) {
        self.enabled = enabled
        self.messageEdit = messageEdit
        self.label = label
        self.buttonStyles = buttonStyles
        self.hideInputSendButton = hideInputSendButton
        self.overwriteEnterClick = overwriteEnterClick
    }
}

// MARK: - Message Text Filter

public struct MessageTextFilterConfig {
    public let enabled: Bool
    public let filterFunction: (String) -> String
    
    public init(enabled: Bool, filterFunction: @escaping (String) -> String) {
        self.enabled = enabled
        self.filterFunction = filterFunction
    }
}

// MARK: - Block Message Sending

public struct BlockMessageSendingConfig {
    public let enabled: Bool
    public let timeout: TimeInterval
    public let onTimeout: ((String) -> Void)?
    
    public init(enabled: Bool, timeout: TimeInterval = 300.0, onTimeout: ((String) -> Void)? = nil) {
        self.enabled = enabled
        self.timeout = timeout
        self.onTimeout = onTimeout
    }
}

// MARK: - Custom Typing Indicator

public enum TypingIndicatorPosition: String, Codable {
    case bottom = "bottom"
    case top = "top"
    case overlay = "overlay"
    case floating = "floating"
}

public struct CustomTypingIndicatorConfig {
    public let enabled: Bool
    public let text: String?
    public let textFunction: (([String]) -> String)?
    public let position: TypingIndicatorPosition?
    public let styles: [String: Any]?
    
    public init(
        enabled: Bool,
        text: String? = nil,
        textFunction: (([String]) -> String)? = nil,
        position: TypingIndicatorPosition? = nil,
        styles: [String: Any]? = nil
    ) {
        self.enabled = enabled
        self.text = text
        self.textFunction = textFunction
        self.position = position
        self.styles = styles
    }
    
    public func getText(usersTyping: [String]) -> String {
        if let textFunction = textFunction {
            return textFunction(usersTyping)
        }
        return text ?? "\(usersTyping.joined(separator: ", ")) \(usersTyping.count == 1 ? "is" : "are") typing..."
    }
}

// MARK: - Disable Chat Info

public struct DisableChatInfoConfig: Codable, Equatable {
    public let disableHeader: Bool?
    public let disableDescription: Bool?
    public let disableType: Bool?
    public let disableMembers: Bool?
    public let hideMembers: Bool?
    public let disableChatHeaderMenu: Bool?
    
    public init(
        disableHeader: Bool? = nil,
        disableDescription: Bool? = nil,
        disableType: Bool? = nil,
        disableMembers: Bool? = nil,
        hideMembers: Bool? = nil,
        disableChatHeaderMenu: Bool? = nil
    ) {
        self.disableHeader = disableHeader
        self.disableDescription = disableDescription
        self.disableType = disableType
        self.disableMembers = disableMembers
        self.hideMembers = hideMembers
        self.disableChatHeaderMenu = disableChatHeaderMenu
    }
}

// MARK: - Chat Header Settings

public struct ChatHeaderSettingsConfig: Codable, Equatable {
    public let hide: Bool?
    public let disableCreate: Bool?
    public let disableMenu: Bool?
    public let hideSearch: Bool?
    
    public init(
        hide: Bool? = nil,
        disableCreate: Bool? = nil,
        disableMenu: Bool? = nil,
        hideSearch: Bool? = nil
    ) {
        self.hide = hide
        self.disableCreate = disableCreate
        self.disableMenu = disableMenu
        self.hideSearch = hideSearch
    }
}

// MARK: - Message Notification Position

public enum NotificationHorizontalPosition: String, Codable {
    case left = "left"
    case right = "right"
    case center = "center"
}

public enum NotificationVerticalPosition: String, Codable {
    case top = "top"
    case bottom = "bottom"
}

public struct NotificationOffset: Codable, Equatable {
    public let top: Double?
    public let bottom: Double?
    public let left: Double?
    public let right: Double?
    
    public init(top: Double? = nil, bottom: Double? = nil, left: Double? = nil, right: Double? = nil) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
    }
}

public struct NotificationPosition: Codable, Equatable {
    public let horizontal: NotificationHorizontalPosition?
    public let vertical: NotificationVerticalPosition?
    public let offset: NotificationOffset?
    
    public init(
        horizontal: NotificationHorizontalPosition? = nil,
        vertical: NotificationVerticalPosition? = nil,
        offset: NotificationOffset? = nil
    ) {
        self.horizontal = horizontal
        self.vertical = vertical
        self.offset = offset
    }
}

// MARK: - Message Notification Config

public struct MessageNotificationConfig {
    public let enabled: Bool?
    public let showInContext: Bool?
    public let position: NotificationPosition?
    public let maxNotifications: Int?
    public let duration: TimeInterval?
    public let onClick: ((MessageNotificationParams) -> Void)?
    
    public init(
        enabled: Bool? = nil,
        showInContext: Bool? = nil,
        position: NotificationPosition? = nil,
        maxNotifications: Int? = nil,
        duration: TimeInterval? = nil,
        onClick: ((MessageNotificationParams) -> Void)? = nil
    ) {
        self.enabled = enabled
        self.showInContext = showInContext
        self.position = position
        self.maxNotifications = maxNotifications
        self.duration = duration
        self.onClick = onClick
    }
}

public struct MessageNotificationParams {
    public let roomJID: String
    public let messageId: String
    public let message: Message
    public let roomName: String
    public let senderName: String
    
    public init(roomJID: String, messageId: String, message: Message, roomName: String, senderName: String) {
        self.roomJID = roomJID
        self.messageId = messageId
        self.message = message
        self.roomName = roomName
        self.senderName = senderName
    }
}

// MARK: - Event Handlers

public struct ChatEventHandlers {
    public let onMessageSent: ((MessageSentEvent) -> Void)?
    public let onMessageFailed: ((MessageFailedEvent) -> Void)?
    public let onMessageEdited: ((MessageEditedEvent) -> Void)?
    
    public init(
        onMessageSent: ((MessageSentEvent) -> Void)? = nil,
        onMessageFailed: ((MessageFailedEvent) -> Void)? = nil,
        onMessageEdited: ((MessageEditedEvent) -> Void)? = nil
    ) {
        self.onMessageSent = onMessageSent
        self.onMessageFailed = onMessageFailed
        self.onMessageEdited = onMessageEdited
    }
}

public struct MessageSentEvent {
    public let message: String
    public let roomJID: String
    public let user: User
    public let messageType: MessageType
    public let metadata: [String: Any]?
    
    public init(message: String, roomJID: String, user: User, messageType: MessageType, metadata: [String: Any]? = nil) {
        self.message = message
        self.roomJID = roomJID
        self.user = user
        self.messageType = messageType
        self.metadata = metadata
    }
}

public struct MessageFailedEvent {
    public let message: String
    public let roomJID: String
    public let error: Error
    public let messageType: MessageType
    
    public init(message: String, roomJID: String, error: Error, messageType: MessageType) {
        self.message = message
        self.roomJID = roomJID
        self.error = error
        self.messageType = messageType
    }
}

public struct MessageEditedEvent {
    public let messageId: String
    public let newMessage: String
    public let roomJID: String
    public let user: User
    
    public init(messageId: String, newMessage: String, roomJID: String, user: User) {
        self.messageId = messageId
        self.newMessage = newMessage
        self.roomJID = roomJID
        self.user = user
    }
}

public enum MessageType: String, Codable {
    case text = "text"
    case media = "media"
}

// MARK: - Enable Rooms Retry

public struct EnableRoomsRetryConfig: Codable, Equatable {
    public let enabled: Bool
    public let helperText: String
    
    public init(enabled: Bool, helperText: String) {
        self.enabled = enabled
        self.helperText = helperText
    }
}

// MARK: - Main Chat Config

public struct ChatConfig {
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
    
    // Event Handlers
    public var eventHandlers: ChatEventHandlers?
    
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
