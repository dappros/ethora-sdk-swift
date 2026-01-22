//
//  UseMessageNotifications.swift
//  XMPPChatCore
//
//  Advanced message notifications
//

import Foundation
import UserNotifications
import Combine

#if os(iOS)
@MainActor
public class MessageNotificationManager: ObservableObject {
    @Published public var notifications: [MessageNotification] = []
    
    private var maxNotifications: Int = 3
    private var duration: TimeInterval = 5.0
    private var timers: [String: Timer] = [:]
    
    public init() {
        requestPermission()
    }
    
    public func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                //print("Notification permission error: \(error)")
            }
        }
    }
    
    public func showNotification(_ notification: MessageNotification, config: MessageNotificationConfig?) {
        // In-app notification
        notifications.removeAll { $0.roomJID == notification.roomJID }
        notifications.append(notification)
        
        if notifications.count > (config?.maxNotifications ?? maxNotifications ?? 3) {
            notifications.removeFirst()
        }
        
        // System notification
        if config?.enabled == true || (config?.enabled == nil && config != nil) {
            let content = UNMutableNotificationContent()
            content.title = notification.roomName
            content.body = "\(notification.senderName): \(notification.messagePreview)"
            content.sound = .default
            content.userInfo = [
                "roomJID": notification.roomJID,
                "messageId": notification.messageId
            ]
            
            let request = UNNotificationRequest(
                identifier: notification.messageId,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
            )
            
            UNUserNotificationCenter.current().add(request)
        }
        
        // Auto-dismiss
        let timer = Timer.scheduledTimer(withTimeInterval: config?.duration ?? duration ?? 5.0, repeats: false) { [weak self] _ in
            self?.dismissNotification(notification.messageId)
        }
        timers[notification.messageId] = timer
    }
    
    public func dismissNotification(_ messageId: String) {
        notifications.removeAll { $0.messageId == messageId }
        timers[messageId]?.invalidate()
        timers.removeValue(forKey: messageId)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [messageId])
    }
    
    public func dismissAll() {
        notifications.removeAll()
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
}
#else
@MainActor
public class MessageNotificationManager: ObservableObject {
    @Published public var notifications: [MessageNotification] = []
    public init() {}
    public func showNotification(_ notification: MessageNotification, config: MessageNotificationConfig?) {}
    public func dismissNotification(_ messageId: String) {}
    public func dismissAll() {}
}
#endif
