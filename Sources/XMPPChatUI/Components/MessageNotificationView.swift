//
//  MessageNotificationView.swift
//  XMPPChatUI
//
//  In-app message notifications
//

import SwiftUI
import XMPPChatCore

public struct MessageNotificationView: View {
    let notification: MessageNotification
    let position: NotificationPosition
    let onTap: (() -> Void)?
    let onDismiss: (() -> Void)?
    
    @State private var isVisible = false
    
    public init(
        notification: MessageNotification,
        position: NotificationPosition,
        onTap: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.notification = notification
        self.position = position
        self.onTap = onTap
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        if isVisible {
            HStack(spacing: 12) {
                // Avatar
                if let avatarURL = notification.senderAvatar,
                   let url = URL(string: avatarURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.blue.opacity(0.3))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(notification.senderName.prefix(1).uppercased())
                                .font(.headline)
                                .foregroundColor(.blue)
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(notification.roomName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(notification.senderName + ": " + notification.messagePreview)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation {
                        isVisible = false
                    }
                    onDismiss?()
                }) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            .padding(.horizontal, 16)
            .onTapGesture {
                onTap?()
            }
            .transition(.move(edge: position.vertical == .top ? .top : .bottom).combined(with: .opacity))
            .onAppear {
                withAnimation(.spring()) {
                    isVisible = true
                }
            }
        }
    }
}

public struct MessageNotification {
    public let roomJID: String
    public let messageId: String
    public let roomName: String
    public let senderName: String
    public let messagePreview: String
    public let senderAvatar: String?
    
    public init(
        roomJID: String,
        messageId: String,
        roomName: String,
        senderName: String,
        messagePreview: String,
        senderAvatar: String? = nil
    ) {
        self.roomJID = roomJID
        self.messageId = messageId
        self.roomName = roomName
        self.senderName = senderName
        self.messagePreview = messagePreview
        self.senderAvatar = senderAvatar
    }
}

@MainActor
public class MessageNotificationManager: ObservableObject {
    @Published var notifications: [MessageNotification] = []
    
    private var maxNotifications: Int = 3
    private var duration: TimeInterval = 5.0
    private var timers: [String: Timer] = [:]
    
    public func showNotification(_ notification: MessageNotification, config: MessageNotificationConfig?) {
        // Remove existing notification for same room
        notifications.removeAll { $0.roomJID == notification.roomJID }
        
        // Add new notification
        notifications.append(notification)
        
        // Limit notifications
        if notifications.count > (config?.maxNotifications ?? maxNotifications) {
            notifications.removeFirst()
        }
        
        // Auto-dismiss after duration
        let timer = Timer.scheduledTimer(withTimeInterval: config?.duration ?? duration, repeats: false) { [weak self] _ in
            self?.dismissNotification(notification.messageId)
        }
        timers[notification.messageId] = timer
    }
    
    public func dismissNotification(_ messageId: String) {
        notifications.removeAll { $0.messageId == messageId }
        timers[messageId]?.invalidate()
        timers.removeValue(forKey: messageId)
    }
    
    public func dismissAll() {
        notifications.removeAll()
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
    }
}
