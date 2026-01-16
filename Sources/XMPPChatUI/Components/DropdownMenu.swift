//
//  DropdownMenu.swift
//  XMPPChatUI
//
//  Dropdown menu component
//

import SwiftUI

public struct DropdownMenu<Content: View>: View {
    let title: String
    let content: Content
    @Binding var isOpen: Bool
    
    public init(
        title: String,
        isOpen: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self._isOpen = isOpen
        self.content = content()
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isOpen.toggle()
                }
            }) {
                HStack {
                    Text(title)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                #if os(iOS)
                .background(Color(uiColor: .systemGray6))
                #else
                .background(Color(NSColor.controlBackgroundColor))
                #endif
            }
            
            if isOpen {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                #if os(iOS)
                .background(Color(uiColor: .systemBackground))
                #else
                .background(Color(NSColor.controlBackgroundColor))
                #endif
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

public struct DropdownMenuItem: View {
    let title: String
    let icon: String?
    let action: () -> Void
    
    public init(
        title: String,
        icon: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                }
                Text(title)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}
