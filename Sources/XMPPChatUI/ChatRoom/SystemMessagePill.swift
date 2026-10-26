//
//  SystemMessagePill.swift
//  XMPPChatUI
//
//  Centered pill for system messages (isSystemMessage="true"), like web SystemMessage.tsx.
//

import SwiftUI

struct SystemMessagePill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.secondary.opacity(0.12)))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }
}
