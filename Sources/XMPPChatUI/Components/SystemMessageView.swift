//
//  SystemMessageView.swift
//  XMPPChatUI
//
//  System message component
//

import SwiftUI
import XMPPChatCore

public struct SystemMessageView: View {
    let message: SystemMessage
    
    public init(message: SystemMessage) {
        self.message = message
    }
    
    public var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 4) {
                if let icon = message.icon {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(message.text)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

public struct SystemMessage {
    public let text: String
    public let type: SystemMessageType
    public let icon: String?
    public let date: Date
    
    public init(
        text: String,
        type: SystemMessageType,
        icon: String? = nil,
        date: Date = Date()
    ) {
        self.text = text
        self.type = type
        self.icon = icon
        self.date = date
    }
    
    public static func userJoined(_ userName: String) -> SystemMessage {
        SystemMessage(
            text: "\(userName) joined",
            type: .userJoined,
            icon: "person.badge.plus"
        )
    }
    
    public static func userLeft(_ userName: String) -> SystemMessage {
        SystemMessage(
            text: "\(userName) left",
            type: .userLeft,
            icon: "person.badge.minus"
        )
    }
    
    public static func roomCreated(_ roomName: String) -> SystemMessage {
        SystemMessage(
            text: "Room \(roomName) was created",
            type: .roomCreated,
            icon: "plus.circle"
        )
    }
    
    public static func messageDeleted(_ userName: String) -> SystemMessage {
        SystemMessage(
            text: "\(userName) deleted a message",
            type: .messageDeleted,
            icon: "trash"
        )
    }
}

public enum SystemMessageType {
    case userJoined
    case userLeft
    case roomCreated
    case messageDeleted
    case custom
}
