//
//  HapticFeedback.swift
//  XMPPChatUI
//
//  Haptic feedback helper for iOS
//

import Foundation
#if os(iOS)
import UIKit

public struct HapticFeedback {
    public static func messageSent() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    public static func messageReceived() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    public static func buttonPress() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    public static func error() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }
    
    public static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
}
#else
public struct HapticFeedback {
    public static func messageSent() {}
    public static func messageReceived() {}
    public static func buttonPress() {}
    public static func error() {}
    public static func selection() {}
}
#endif
