//
//  SafeAreaHelper.swift
//  XMPPChatUI
//
//  Safe area handling helper
//

import SwiftUI

extension View {
    public func safeAreaInsets() -> EdgeInsets {
        #if os(iOS)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            return window.safeAreaInsets
        }
        #endif
        return EdgeInsets()
    }
}

#if os(iOS)
extension UIApplication {
    var keyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}

extension UIWindow {
    var safeAreaInsets: EdgeInsets {
        EdgeInsets(
            top: safeAreaInsets.top,
            leading: safeAreaInsets.left,
            bottom: safeAreaInsets.bottom,
            trailing: safeAreaInsets.right
        )
    }
}
#endif
