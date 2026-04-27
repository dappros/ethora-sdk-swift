//
//  ConfigStore.swift
//  XMPPChatCore
//
//  Global configuration store for chat component
//

import Foundation
import Combine
import SwiftUI

@MainActor
public class ConfigStore: ObservableObject {
    public static let shared = ConfigStore()
    
    @Published public var config: ChatConfig
    
    private let userDefaults = UserDefaults.standard
    private let configKey = "ethora_chat_config"
    
    private init() {
        // Load saved config or create default
        if let savedData = userDefaults.data(forKey: configKey),
           let savedConfig = try? JSONDecoder().decode(ChatConfig.self, from: savedData) {
            self.config = savedConfig
        } else {
            self.config = ChatConfig()
        }
        forceethoradev()
    }
    
    /// Update configuration
    public func updateConfig(_ newConfig: ChatConfig) {
        self.config = newConfig
        saveConfig()
    }
    
    /// Merge configuration with existing
    public func mergeConfig(_ partialConfig: ChatConfig) {
        // Merge non-nil values from partialConfig into existing config
        if let disableHeader = partialConfig.disableHeader {
            config.disableHeader = disableHeader
        }
        if let disableMedia = partialConfig.disableMedia {
            config.disableMedia = disableMedia
        }
        if let colors = partialConfig.colors {
            config.colors = colors
        }
        if let googleLogin = partialConfig.googleLogin {
            config.googleLogin = googleLogin
        }
        if let jwtLogin = partialConfig.jwtLogin {
            config.jwtLogin = jwtLogin
        }
        if let userLogin = partialConfig.userLogin {
            config.userLogin = userLogin
        }
        if let customLogin = partialConfig.customLogin {
            config.customLogin = customLogin
        }
        if let baseUrl = partialConfig.baseUrl {
            config.baseUrl = baseUrl
        }
        if let appId = partialConfig.appId {
            config.appId = appId
        }
        if let customAppToken = partialConfig.customAppToken {
            config.customAppToken = customAppToken
        }
        if let xmppSettings = partialConfig.xmppSettings {
            config.xmppSettings = xmppSettings
        }
        if let disableRooms = partialConfig.disableRooms {
            config.disableRooms = disableRooms
        }
        if let defaultLogin = partialConfig.defaultLogin {
            config.defaultLogin = defaultLogin
        }
        if let disableInteractions = partialConfig.disableInteractions {
            config.disableInteractions = disableInteractions
        }
        if let chatHeaderBurgerMenu = partialConfig.chatHeaderBurgerMenu {
            config.chatHeaderBurgerMenu = chatHeaderBurgerMenu
        }
        if let forceSetRoom = partialConfig.forceSetRoom {
            config.forceSetRoom = forceSetRoom
        }
        if let setRoomJidInPath = partialConfig.setRoomJidInPath {
            config.setRoomJidInPath = setRoomJidInPath
        }
        if let disableRoomMenu = partialConfig.disableRoomMenu {
            config.disableRoomMenu = disableRoomMenu
        }
        if let disableRoomConfig = partialConfig.disableRoomConfig {
            config.disableRoomConfig = disableRoomConfig
        }
        if let disableNewChatButton = partialConfig.disableNewChatButton {
            config.disableNewChatButton = disableNewChatButton
        }
        if let roomListStyles = partialConfig.roomListStyles {
            config.roomListStyles = roomListStyles
        }
        if let chatRoomStyles = partialConfig.chatRoomStyles {
            config.chatRoomStyles = chatRoomStyles
        }
        if let backgroundChat = partialConfig.backgroundChat {
            config.backgroundChat = backgroundChat
        }
        if let bubleMessage = partialConfig.bubleMessage {
            config.bubleMessage = bubleMessage
        }
        if let headerLogo = partialConfig.headerLogo {
            config.headerLogo = headerLogo
        }
        if let defaultRooms = partialConfig.defaultRooms {
            config.defaultRooms = defaultRooms
        }
        if let customRooms = partialConfig.customRooms {
            config.customRooms = customRooms
        }
        if let refreshTokens = partialConfig.refreshTokens {
            config.refreshTokens = refreshTokens
        }
        if let translates = partialConfig.translates {
            config.translates = translates
        }
        if let disableProfilesInteractions = partialConfig.disableProfilesInteractions {
            config.disableProfilesInteractions = disableProfilesInteractions
        }
        if let disableUserCount = partialConfig.disableUserCount {
            config.disableUserCount = disableUserCount
        }
        if let clearStoreBeforeInit = partialConfig.clearStoreBeforeInit {
            config.clearStoreBeforeInit = clearStoreBeforeInit
        }
        if let disableSentLogic = partialConfig.disableSentLogic {
            config.disableSentLogic = disableSentLogic
        }
        if let initBeforeLoad = partialConfig.initBeforeLoad {
            config.initBeforeLoad = initBeforeLoad
        }
        if let newArch = partialConfig.newArch {
            config.newArch = newArch
        }
        if let qrUrl = partialConfig.qrUrl {
            config.qrUrl = qrUrl
        }
        if let secondarySendButton = partialConfig.secondarySendButton {
            config.secondarySendButton = secondarySendButton
        }
        if let enableRoomsRetry = partialConfig.enableRoomsRetry {
            config.enableRoomsRetry = enableRoomsRetry
        }
        if let chatHeaderAdditional = partialConfig.chatHeaderAdditional {
            config.chatHeaderAdditional = chatHeaderAdditional
        }
        if let botMessageAutoScroll = partialConfig.botMessageAutoScroll {
            config.botMessageAutoScroll = botMessageAutoScroll
        }
        if let messageTextFilter = partialConfig.messageTextFilter {
            config.messageTextFilter = messageTextFilter
        }
        if let whitelistSystemMessage = partialConfig.whitelistSystemMessage {
            config.whitelistSystemMessage = whitelistSystemMessage
        }
        if let disableTypingIndicator = partialConfig.disableTypingIndicator {
            config.disableTypingIndicator = disableTypingIndicator
        }
        if let customTypingIndicator = partialConfig.customTypingIndicator {
            config.customTypingIndicator = customTypingIndicator
        }
        if let blockMessageSendingWhenProcessing = partialConfig.blockMessageSendingWhenProcessing {
            config.blockMessageSendingWhenProcessing = blockMessageSendingWhenProcessing
        }
        if let disableChatInfo = partialConfig.disableChatInfo {
            config.disableChatInfo = disableChatInfo
        }
        if let chatHeaderSettings = partialConfig.chatHeaderSettings {
            config.chatHeaderSettings = chatHeaderSettings
        }
        if let useStoreConsoleEnabled = partialConfig.useStoreConsoleEnabled {
            config.useStoreConsoleEnabled = useStoreConsoleEnabled
        }
        if let messageNotifications = partialConfig.messageNotifications {
            config.messageNotifications = messageNotifications
        }
        if let eventHandlers = partialConfig.eventHandlers {
            config.eventHandlers = eventHandlers
        }
        if let push = partialConfig.push {
            config.push = push
        }
        
        saveConfig()
    }
    
    /// Save configuration to UserDefaults
    private func saveConfig() {
        do {
            let data = try JSONEncoder().encode(config)
            userDefaults.set(data, forKey: configKey)
        } catch {
            // Ignore persistence failures for non-critical runtime state.
        }
    }
    
    /// Reset to default configuration
    public func reset() {
        self.config = ChatConfig()
        userDefaults.removeObject(forKey: configKey)
    }

    /// Force single environment to chat.ethora to avoid mixed API/XMPP runtime state.
    public func forceethoradev() {
        config.baseUrl = AppConfig.defaultBaseURL.absoluteString
        config.appId = AppConfig.defaultAppId
        config.xmppSettings = AppConfig.defaultXMPPSettings
        saveConfig()
    }
}

// MARK: - ChatConfig Codable Extension

extension ChatConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case disableHeader, disableMedia, colors
        case googleLogin, jwtLogin, userLogin
        case baseUrl, appId, customAppToken, xmppSettings
        case disableRooms, defaultLogin, disableInteractions
        case chatHeaderBurgerMenu, forceSetRoom, setRoomJidInPath
        case disableRoomMenu, disableRoomConfig, disableNewChatButton
        case backgroundChat, bubleMessage, headerLogo
        case translates, disableProfilesInteractions, disableUserCount
        case clearStoreBeforeInit, disableSentLogic, initBeforeLoad
        case newArch, qrUrl, enableRoomsRetry
        case botMessageAutoScroll, whitelistSystemMessage
        case disableTypingIndicator, disableChatInfo, chatHeaderSettings
        case useStoreConsoleEnabled
        case push
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.disableHeader = try container.decodeIfPresent(Bool.self, forKey: .disableHeader)
        self.disableMedia = try container.decodeIfPresent(Bool.self, forKey: .disableMedia)
        self.colors = try container.decodeIfPresent(ChatColors.self, forKey: .colors)
        self.googleLogin = try container.decodeIfPresent(GoogleLoginConfig.self, forKey: .googleLogin)
        self.jwtLogin = try container.decodeIfPresent(JWTLoginConfig.self, forKey: .jwtLogin)
        self.userLogin = try container.decodeIfPresent(UserLoginConfig.self, forKey: .userLogin)
        self.baseUrl = try container.decodeIfPresent(String.self, forKey: .baseUrl)
        self.appId = try container.decodeIfPresent(String.self, forKey: .appId)
        self.customAppToken = try container.decodeIfPresent(String.self, forKey: .customAppToken)
        self.xmppSettings = try container.decodeIfPresent(XMPPSettings.self, forKey: .xmppSettings)
        self.disableRooms = try container.decodeIfPresent(Bool.self, forKey: .disableRooms)
        self.defaultLogin = try container.decodeIfPresent(Bool.self, forKey: .defaultLogin)
        self.disableInteractions = try container.decodeIfPresent(Bool.self, forKey: .disableInteractions)
        self.chatHeaderBurgerMenu = try container.decodeIfPresent(Bool.self, forKey: .chatHeaderBurgerMenu)
        self.forceSetRoom = try container.decodeIfPresent(Bool.self, forKey: .forceSetRoom)
        self.setRoomJidInPath = try container.decodeIfPresent(Bool.self, forKey: .setRoomJidInPath)
        self.disableRoomMenu = try container.decodeIfPresent(Bool.self, forKey: .disableRoomMenu)
        self.disableRoomConfig = try container.decodeIfPresent(Bool.self, forKey: .disableRoomConfig)
        self.disableNewChatButton = try container.decodeIfPresent(Bool.self, forKey: .disableNewChatButton)
        self.backgroundChat = try container.decodeIfPresent(BackgroundChatConfig.self, forKey: .backgroundChat)
        self.bubleMessage = try container.decodeIfPresent(MessageBubbleStyle.self, forKey: .bubleMessage)
        self.headerLogo = try container.decodeIfPresent(String.self, forKey: .headerLogo)
        self.translates = try container.decodeIfPresent(TranslationsConfig.self, forKey: .translates)
        self.disableProfilesInteractions = try container.decodeIfPresent(Bool.self, forKey: .disableProfilesInteractions)
        self.disableUserCount = try container.decodeIfPresent(Bool.self, forKey: .disableUserCount)
        self.clearStoreBeforeInit = try container.decodeIfPresent(Bool.self, forKey: .clearStoreBeforeInit)
        self.disableSentLogic = try container.decodeIfPresent(Bool.self, forKey: .disableSentLogic)
        self.initBeforeLoad = try container.decodeIfPresent(Bool.self, forKey: .initBeforeLoad)
        self.newArch = try container.decodeIfPresent(Bool.self, forKey: .newArch)
        self.qrUrl = try container.decodeIfPresent(String.self, forKey: .qrUrl)
        self.enableRoomsRetry = try container.decodeIfPresent(EnableRoomsRetryConfig.self, forKey: .enableRoomsRetry)
        self.botMessageAutoScroll = try container.decodeIfPresent(Bool.self, forKey: .botMessageAutoScroll)
        self.whitelistSystemMessage = try container.decodeIfPresent([String].self, forKey: .whitelistSystemMessage)
        self.disableTypingIndicator = try container.decodeIfPresent(Bool.self, forKey: .disableTypingIndicator)
        self.disableChatInfo = try container.decodeIfPresent(DisableChatInfoConfig.self, forKey: .disableChatInfo)
        self.chatHeaderSettings = try container.decodeIfPresent(ChatHeaderSettingsConfig.self, forKey: .chatHeaderSettings)
        self.useStoreConsoleEnabled = try container.decodeIfPresent(Bool.self, forKey: .useStoreConsoleEnabled)
        self.push = try container.decodeIfPresent(PushNotificationConfig.self, forKey: .push)
        
        // Non-codable properties initialized to nil
        self.customLogin = nil
        self.roomListStyles = nil
        self.chatRoomStyles = nil
        self.headerMenu = nil
        self.headerChatMenu = nil
        self.defaultRooms = nil
        self.customRooms = nil
        self.refreshTokens = nil
        self.secondarySendButton = nil
        self.chatHeaderAdditional = nil
        self.messageTextFilter = nil
        self.customTypingIndicator = nil
        self.blockMessageSendingWhenProcessing = nil
        self.messageNotifications = nil
        self.eventHandlers = nil
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(disableHeader, forKey: .disableHeader)
        try container.encodeIfPresent(disableMedia, forKey: .disableMedia)
        try container.encodeIfPresent(colors, forKey: .colors)
        try container.encodeIfPresent(googleLogin, forKey: .googleLogin)
        try container.encodeIfPresent(jwtLogin, forKey: .jwtLogin)
        try container.encodeIfPresent(userLogin, forKey: .userLogin)
        try container.encodeIfPresent(baseUrl, forKey: .baseUrl)
        try container.encodeIfPresent(appId, forKey: .appId)
        try container.encodeIfPresent(customAppToken, forKey: .customAppToken)
        try container.encodeIfPresent(xmppSettings, forKey: .xmppSettings)
        try container.encodeIfPresent(disableRooms, forKey: .disableRooms)
        try container.encodeIfPresent(defaultLogin, forKey: .defaultLogin)
        try container.encodeIfPresent(disableInteractions, forKey: .disableInteractions)
        try container.encodeIfPresent(chatHeaderBurgerMenu, forKey: .chatHeaderBurgerMenu)
        try container.encodeIfPresent(forceSetRoom, forKey: .forceSetRoom)
        try container.encodeIfPresent(setRoomJidInPath, forKey: .setRoomJidInPath)
        try container.encodeIfPresent(disableRoomMenu, forKey: .disableRoomMenu)
        try container.encodeIfPresent(disableRoomConfig, forKey: .disableRoomConfig)
        try container.encodeIfPresent(disableNewChatButton, forKey: .disableNewChatButton)
        try container.encodeIfPresent(backgroundChat, forKey: .backgroundChat)
        try container.encodeIfPresent(bubleMessage, forKey: .bubleMessage)
        try container.encodeIfPresent(headerLogo, forKey: .headerLogo)
        try container.encodeIfPresent(translates, forKey: .translates)
        try container.encodeIfPresent(disableProfilesInteractions, forKey: .disableProfilesInteractions)
        try container.encodeIfPresent(disableUserCount, forKey: .disableUserCount)
        try container.encodeIfPresent(clearStoreBeforeInit, forKey: .clearStoreBeforeInit)
        try container.encodeIfPresent(disableSentLogic, forKey: .disableSentLogic)
        try container.encodeIfPresent(initBeforeLoad, forKey: .initBeforeLoad)
        try container.encodeIfPresent(newArch, forKey: .newArch)
        try container.encodeIfPresent(qrUrl, forKey: .qrUrl)
        try container.encodeIfPresent(enableRoomsRetry, forKey: .enableRoomsRetry)
        try container.encodeIfPresent(botMessageAutoScroll, forKey: .botMessageAutoScroll)
        try container.encodeIfPresent(whitelistSystemMessage, forKey: .whitelistSystemMessage)
        try container.encodeIfPresent(disableTypingIndicator, forKey: .disableTypingIndicator)
        try container.encodeIfPresent(disableChatInfo, forKey: .disableChatInfo)
        try container.encodeIfPresent(chatHeaderSettings, forKey: .chatHeaderSettings)
        try container.encodeIfPresent(useStoreConsoleEnabled, forKey: .useStoreConsoleEnabled)
        try container.encodeIfPresent(push, forKey: .push)
    }
}
