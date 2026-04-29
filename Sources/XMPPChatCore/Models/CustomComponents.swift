//
//  CustomComponents.swift
//  XMPPChatCore
//
//  Custom components protocol for component injection
//

import Foundation
import SwiftUI

// MARK: - Day Separator Props

public struct DaySeparatorProps {
    public let date: Date
    public let formattedDate: String
    
    public init(date: Date, formattedDate: String) {
        self.date = date
        self.formattedDate = formattedDate
    }
}

// MARK: - New Message Label Props

public struct NewMessageLabelProps {
    public let color: String?
    
    public init(color: String? = nil) {
        self.color = color
    }
}

// MARK: - Decorated Message

public struct DecoratedMessage {
    public let message: Message
    public let showDateLabel: Bool
    
    public init(message: Message, showDateLabel: Bool) {
        self.message = message
        self.showDateLabel = showDateLabel
    }
}

// MARK: - Scroll Controller API

public protocol ScrollControllerAPI {
    func scrollToBottom()
    func waitForImagesLoaded() async
    var showScrollButton: Bool { get }
    var newMessagesCount: Int { get }
    func resetNewMessageCounter()
}

// MARK: - Custom Scrollable Area Props

public struct CustomScrollableAreaProps {
    public let roomJID: String
    public let messages: [Message]
    public let decoratedMessages: [DecoratedMessage]
    public let isLoading: Bool
    public let isReply: Bool
    public let activeMessage: Message?
    public let loadMoreMessages: (String, Int, Int?) async -> Void
    public let renderMessage: (DecoratedMessage) -> AnyView
    public let scrollController: ScrollControllerAPI
    public let typingIndicator: AnyView?
    public let config: ChatConfig?
    
    public init(
        roomJID: String,
        messages: [Message],
        decoratedMessages: [DecoratedMessage],
        isLoading: Bool,
        isReply: Bool,
        activeMessage: Message?,
        loadMoreMessages: @escaping (String, Int, Int?) async -> Void,
        renderMessage: @escaping (DecoratedMessage) -> AnyView,
        scrollController: ScrollControllerAPI,
        typingIndicator: AnyView?,
        config: ChatConfig?
    ) {
        self.roomJID = roomJID
        self.messages = messages
        self.decoratedMessages = decoratedMessages
        self.isLoading = isLoading
        self.isReply = isReply
        self.activeMessage = activeMessage
        self.loadMoreMessages = loadMoreMessages
        self.renderMessage = renderMessage
        self.scrollController = scrollController
        self.typingIndicator = typingIndicator
        self.config = config
    }
}

// MARK: - Message Props

public struct MessageProps {
    public let message: Message
    public let isUser: Bool
    public let isReply: Bool
    
    public init(message: Message, isUser: Bool, isReply: Bool) {
        self.message = message
        self.isUser = isUser
        self.isReply = isReply
    }
}

// MARK: - Send Input Props

public struct SendInputProps {
    public let onSendMessage: ((String) -> Void)?
    /// Sends an attachment. The optional third argument is the caption typed alongside
    /// the attachment — when non-empty it is delivered as a separate text message right
    /// after the media stanza.
    public let onSendMedia: ((Data, String, String?) -> Void)?
    public let placeholderText: String?
    public let messageText: Binding<String>
    public let isEditing: Bool
    public let editMessageId: String?

    public init(
        onSendMessage: ((String) -> Void)? = nil,
        onSendMedia: ((Data, String, String?) -> Void)? = nil,
        placeholderText: String? = nil,
        messageText: Binding<String>,
        isEditing: Bool = false,
        editMessageId: String? = nil
    ) {
        self.onSendMessage = onSendMessage
        self.onSendMedia = onSendMedia
        self.placeholderText = placeholderText
        self.messageText = messageText
        self.isEditing = isEditing
        self.editMessageId = editMessageId
    }
}

// MARK: - Custom Components Protocol

public protocol CustomComponentsProtocol {
    var customMessageComponent: ((MessageProps) -> AnyView)? { get }
    var customInputComponent: ((SendInputProps) -> AnyView)? { get }
    var customScrollableArea: ((CustomScrollableAreaProps) -> AnyView)? { get }
    var customDaySeparator: ((DaySeparatorProps) -> AnyView)? { get }
    var customNewMessageLabel: ((NewMessageLabelProps) -> AnyView)? { get }
}

// MARK: - Default Custom Components

public struct DefaultCustomComponents: CustomComponentsProtocol {
    public let customMessageComponent: ((MessageProps) -> AnyView)?
    public let customInputComponent: ((SendInputProps) -> AnyView)?
    public let customScrollableArea: ((CustomScrollableAreaProps) -> AnyView)?
    public let customDaySeparator: ((DaySeparatorProps) -> AnyView)?
    public let customNewMessageLabel: ((NewMessageLabelProps) -> AnyView)?
    
    public init(
        customMessageComponent: ((MessageProps) -> AnyView)? = nil,
        customInputComponent: ((SendInputProps) -> AnyView)? = nil,
        customScrollableArea: ((CustomScrollableAreaProps) -> AnyView)? = nil,
        customDaySeparator: ((DaySeparatorProps) -> AnyView)? = nil,
        customNewMessageLabel: ((NewMessageLabelProps) -> AnyView)? = nil
    ) {
        self.customMessageComponent = customMessageComponent
        self.customInputComponent = customInputComponent
        self.customScrollableArea = customScrollableArea
        self.customDaySeparator = customDaySeparator
        self.customNewMessageLabel = customNewMessageLabel
    }
}
