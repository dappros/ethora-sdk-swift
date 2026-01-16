//
//  SafeAreaHelper.swift
//  XMPPChatUI
//
//  Safe area handling helper
//

import SwiftUI

#if os(iOS)
import UIKit

extension View {
    public func getSafeAreaInsets() -> EdgeInsets {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            let uiInsets = window.safeAreaInsets
            return EdgeInsets(
                top: uiInsets.top,
                leading: uiInsets.left,
                bottom: uiInsets.bottom,
                trailing: uiInsets.right
            )
        }
        return EdgeInsets()
    }
}

extension UIApplication {
    var keyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}
#else
extension View {
    public func getSafeAreaInsets() -> EdgeInsets {
        return EdgeInsets()
    }
}
#endif
