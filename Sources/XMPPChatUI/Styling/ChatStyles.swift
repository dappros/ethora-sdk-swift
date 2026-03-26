//
//  ChatStyles.swift
//  XMPPChatUI
//
//  Styling system for chat component
//

import SwiftUI
import XMPPChatCore

public struct ChatStyles {
    public let colors: ChatColors
    public let roomListStyles: RoomListStyles?
    public let chatRoomStyles: ChatRoomStyles?
    public let backgroundChat: BackgroundChatConfig?
    public let messageBubble: MessageBubbleStyle?
    
    public init(
        colors: ChatColors? = nil,
        roomListStyles: RoomListStyles? = nil,
        chatRoomStyles: ChatRoomStyles? = nil,
        backgroundChat: BackgroundChatConfig? = nil,
        messageBubble: MessageBubbleStyle? = nil
    ) {
        self.colors = colors ?? ChatColors(primary: "#0052CD", secondary: "#F3F6FC")
        self.roomListStyles = roomListStyles
        self.chatRoomStyles = chatRoomStyles
        self.backgroundChat = backgroundChat
        self.messageBubble = messageBubble
    }
    
    public static let `default` = ChatStyles()
}

public struct RoomListStyles {
    public let backgroundColor: Color?
    public let cornerRadius: CGFloat?
    public let borderWidth: CGFloat?
    public let borderColor: Color?
    public let padding: EdgeInsets?
    
    public init(
        backgroundColor: Color? = nil,
        cornerRadius: CGFloat? = nil,
        borderWidth: CGFloat? = nil,
        borderColor: Color? = nil,
        padding: EdgeInsets? = nil
    ) {
        self.backgroundColor = backgroundColor
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.borderColor = borderColor
        self.padding = padding
    }
}

public extension RoomListStyles {
    init?(dictionary: [String: Any]?) {
        guard let dictionary else { return nil }
        let backgroundColor = (dictionary["backgroundColor"] as? String).map { Color(hex: $0) }
        let cornerRadius = (dictionary["cornerRadius"] as? Double).map { CGFloat($0) }
        let borderWidth = (dictionary["borderWidth"] as? Double).map { CGFloat($0) }
        let borderColor = (dictionary["borderColor"] as? String).map { Color(hex: $0) }
        self.init(
            backgroundColor: backgroundColor,
            cornerRadius: cornerRadius,
            borderWidth: borderWidth,
            borderColor: borderColor,
            padding: nil
        )
    }
}

public struct ChatRoomStyles {
    public let backgroundColor: Color?
    public let cornerRadius: CGFloat?
    public let borderWidth: CGFloat?
    public let borderColor: Color?
    public let padding: EdgeInsets?
    
    public init(
        backgroundColor: Color? = nil,
        cornerRadius: CGFloat? = nil,
        borderWidth: CGFloat? = nil,
        borderColor: Color? = nil,
        padding: EdgeInsets? = nil
    ) {
        self.backgroundColor = backgroundColor
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.borderColor = borderColor
        self.padding = padding
    }
}

public extension ChatRoomStyles {
    init?(dictionary: [String: Any]?) {
        guard let dictionary else { return nil }
        let backgroundColor = (dictionary["backgroundColor"] as? String).map { Color(hex: $0) }
        let cornerRadius = (dictionary["cornerRadius"] as? Double).map { CGFloat($0) }
        let borderWidth = (dictionary["borderWidth"] as? Double).map { CGFloat($0) }
        let borderColor = (dictionary["borderColor"] as? String).map { Color(hex: $0) }
        self.init(
            backgroundColor: backgroundColor,
            cornerRadius: cornerRadius,
            borderWidth: borderWidth,
            borderColor: borderColor,
            padding: nil
        )
    }
}

// MARK: - Style Modifiers

extension View {
    public func applyChatRoomStyles(_ styles: ChatRoomStyles?) -> some View {
        guard let styles = styles else { return AnyView(self) }
        
        var view: AnyView = AnyView(self)
        
        if let backgroundColor = styles.backgroundColor {
            view = AnyView(view.background(backgroundColor))
        }
        
        if let cornerRadius = styles.cornerRadius {
            view = AnyView(view.cornerRadius(cornerRadius))
        }
        
        if let borderWidth = styles.borderWidth, let borderColor = styles.borderColor {
            view = AnyView(view.border(borderColor, width: borderWidth))
        }
        
        if let padding = styles.padding {
            view = AnyView(view.padding(padding))
        }
        
        return view
    }
    
    public func applyRoomListStyles(_ styles: RoomListStyles?) -> some View {
        guard let styles = styles else { return AnyView(self) }
        
        var view: AnyView = AnyView(self)
        
        if let backgroundColor = styles.backgroundColor {
            view = AnyView(view.background(backgroundColor))
        }
        
        if let cornerRadius = styles.cornerRadius {
            view = AnyView(view.cornerRadius(cornerRadius))
        }
        
        if let borderWidth = styles.borderWidth, let borderColor = styles.borderColor {
            view = AnyView(view.border(borderColor, width: borderWidth))
        }
        
        if let padding = styles.padding {
            view = AnyView(view.padding(padding))
        }
        
        return view
    }
}
