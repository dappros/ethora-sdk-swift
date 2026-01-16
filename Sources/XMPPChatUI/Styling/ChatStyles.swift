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
        self.colors = colors ?? ChatColors(primary: "#5E3FDE", secondary: "#E1E4FE")
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
