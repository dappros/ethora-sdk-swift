//
//  ChatLayout.swift
//  XMPPChatUI
//
//  Decides when the room list and the open chat sit side by side (iPad at
//  regular width). Phones and iPad split-view keep the stacked layout.
//

import SwiftUI
import XMPPChatCore

enum ChatLayoutPolicy {
    /// True when the room list and the open chat should sit side by side.
    ///
    /// - `supportsTablet == false` always gives the stacked layout.
    /// - Otherwise the split applies only on iPad at regular horizontal size
    ///   class (full screen, or a wide split view).
    static func usesSideBySide(
        supportsTablet: Bool?,
        isPad: Bool,
        horizontalSizeClass: UserInterfaceSizeClass?
    ) -> Bool {
        guard supportsTablet != false, isPad else { return false }
        return horizontalSizeClass == .regular
    }

    @MainActor
    static var isPad: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }
}

/// Right-hand pane shown in the side-by-side layout until a room is picked.
struct ChatDetailPlaceholder: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("Select a chat")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
