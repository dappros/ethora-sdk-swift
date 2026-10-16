//
//  NotificationConfig.swift
//  XMPPChatCore
//

import Foundation

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

/// `pushNotifications` config, same key names as the web and RN SDKs.
public struct PushNotificationsConfig {
    /// `false` switches push off (no registration, no room subscriptions). Unset means on.
    public let enabled: Bool?
    /// Push gateway base URL, version segment included (e.g. `https://push.example.com/api/v1`).
    /// Unset: the SDK registers tokens directly with the Ethora backend. Needs `ChatConfig.projectName`.
    public let apiUrl: String?
    public let iconPath: String?
    public let badgePath: String?
    /// Host-supplied device tokens. Called once per signed-in user; each returned token is registered.
    /// The iOS SDK has no Firebase dependency, so an FCM token comes from here (or `PushNotificationManager.registerPushToken`).
    public let getPushTokens: (() async -> [PushTokenRegistration]?)?

    public init(
        enabled: Bool? = nil,
        apiUrl: String? = nil,
        iconPath: String? = nil,
        badgePath: String? = nil,
        getPushTokens: (() async -> [PushTokenRegistration]?)? = nil
    ) {
        self.enabled = enabled
        self.apiUrl = apiUrl
        self.iconPath = iconPath
        self.badgePath = badgePath
        self.getPushTokens = getPushTokens
    }
}

public struct PushNotificationConfig: Codable, Equatable {
    public let enabled: Bool
    public let appId: String?
    public let pushBaseURL: String?
    
    public init(enabled: Bool, appId: String? = nil, pushBaseURL: String? = nil) {
        self.enabled = enabled
        self.appId = appId
        self.pushBaseURL = pushBaseURL
    }
}
