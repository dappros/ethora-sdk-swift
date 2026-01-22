//
//  ContextMenuView.swift
//  XMPPChatUI
//
//  Context menu for messages
//

import SwiftUI
import XMPPChatCore

public struct MessageContextMenu: ViewModifier {
    let message: Message
    let isUser: Bool
    let onReply: (() -> Void)?
    let onCopy: (() -> Void)?
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?
    let onReport: (() -> Void)?
    let onForward: (() -> Void)?
    let onPin: (() -> Void)?
    let onStar: (() -> Void)?
    
    public func body(content: Content) -> some View {
        content
            .contextMenu {
                // if let onReply = onReply {
                //     Button(action: onReply) {
                //         Label("Reply", systemImage: "arrowshape.turn.up.left")
                //     }
                // }
                
                if let onCopy = onCopy {
                    Button(action: onCopy) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
                
                if isUser, let onEdit = onEdit {
                    Button(action: onEdit) {
                        Label("Edit", systemImage: "pencil")
                    }
                }
                
                if isUser, let onDelete = onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                }
                
                if let onForward = onForward {
                    Button(action: onForward) {
                        Label("Forward", systemImage: "arrowshape.turn.up.right")
                    }
                }
                
//                if let onReport = onReport {
//                    Button(role: .destructive, action: onReport) {
//                        Label("Report", systemImage: "exclamationmark.triangle")
//                    }
//                }
                
                if let onPin = onPin {
                    Button(action: onPin) {
                        Label("Pin", systemImage: "pin")
                    }
                }
                
                if let onStar = onStar {
                    Button(action: onStar) {
                        Label("Star", systemImage: "star")
                    }
                }
            }
    }
}

extension View {
    public func messageContextMenu(
        message: Message,
        isUser: Bool,
        onReply: (() -> Void)? = nil,
        onCopy: (() -> Void)? = nil,
        onEdit: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onReport: (() -> Void)? = nil,
        onForward: (() -> Void)? = nil,
        onPin: (() -> Void)? = nil,
        onStar: (() -> Void)? = nil
    ) -> some View {
        self.modifier(MessageContextMenu(
            message: message,
            isUser: isUser,
            onReply: onReply,
            onCopy: onCopy,
            onEdit: onEdit,
            onDelete: onDelete,
            onReport: onReport,
            onForward: onForward,
            onPin: onPin,
            onStar: onStar
        ))
    }
}
