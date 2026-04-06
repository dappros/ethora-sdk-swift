//
//  ChatTabView.swift
//  SDKPlayground
//

import SwiftUI
import XMPPChatCore
import XMPPChatUI

struct ChatTabView: View {
    @EnvironmentObject private var session: PlaygroundSession

    var body: some View {
        Group {
            if session.isConnected {
                ChatWrapperView(
                    config: session.buildChatConfig(),
                    initialRoomJID: session.initialRoomJIDForChatWrapper
                )
                    .id(session.chatInstanceId)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Not connected")
                        .font(.headline)
                    Text("Use the Setup tab to connect. After a successful login, the chat UI loads here.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
