//
//  NewMessageLabel.swift
//  XMPPChatUI
//
//  New message label component
//

import SwiftUI
import XMPPChatCore

public struct NewMessageLabel: View {
    let customComponent: ((NewMessageLabelProps) -> AnyView)?
    
    public init(customComponent: ((NewMessageLabelProps) -> AnyView)? = nil) {
        self.customComponent = customComponent
    }
    
    public var body: some View {
        if let customComponent = customComponent {
            customComponent(NewMessageLabelProps())
        } else {
            DefaultNewMessageLabel()
        }
    }
}

struct DefaultNewMessageLabel: View {
    var body: some View {
        HStack {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 1)
            
            Text("New messages")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                #if os(iOS)
                .background(Color(uiColor: .systemGray6))
                #else
                .background(Color(NSColor.controlBackgroundColor))
                #endif
                .cornerRadius(12)
            
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 1)
        }
        .padding(.vertical, 8)
    }
}
