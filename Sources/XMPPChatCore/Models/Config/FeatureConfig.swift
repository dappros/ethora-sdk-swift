//
//  FeatureConfig.swift
//  XMPPChatCore
//

import Foundation
import SwiftUI

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

public struct MessageTextFilterConfig {
    public let enabled: Bool
    public let filterFunction: (String) -> String
    
    public init(enabled: Bool, filterFunction: @escaping (String) -> String) {
        self.enabled = enabled
        self.filterFunction = filterFunction
    }
}

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

public struct EnableRoomsRetryConfig: Codable, Equatable {
    public let enabled: Bool
    public let helperText: String
    
    public init(enabled: Bool, helperText: String) {
        self.enabled = enabled
        self.helperText = helperText
    }
}
