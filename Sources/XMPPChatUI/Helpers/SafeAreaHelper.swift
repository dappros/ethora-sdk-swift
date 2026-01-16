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
    /// Get safe area insets using GeometryReader (recommended approach)
    public func safeAreaInsets() -> some View {
        self.background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: SafeAreaInsetsKey.self,
                    value: geometry.safeAreaInsets
                )
            }
        )
    }
    
    /// Legacy method - use GeometryReader instead to avoid view hierarchy warnings
    @available(*, deprecated, message: "Use GeometryReader with safeAreaInsets preference key instead")
    public func getSafeAreaInsets() -> EdgeInsets {
        // Avoid accessing UIApplication during view body evaluation
        // This can cause _UIReparentingView warnings
        return EdgeInsets()
    }
}

private struct SafeAreaInsetsKey: PreferenceKey {
    static var defaultValue: EdgeInsets = EdgeInsets()
    static func reduce(value: inout EdgeInsets, nextValue: () -> EdgeInsets) {
        value = nextValue()
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
    
    public func safeAreaInsets() -> some View {
        self
    }
}
#endif
