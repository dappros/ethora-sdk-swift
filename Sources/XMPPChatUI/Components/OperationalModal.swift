//
//  OperationalModal.swift
//  XMPPChatUI
//
//  Operational modal component
//

import SwiftUI

public struct OperationalModal<Content: View>: View {
    let title: String
    let content: Content
    let onClose: () -> Void
    @Binding var isPresented: Bool
    
    public init(
        title: String,
        isPresented: Binding<Bool>,
        onClose: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self._isPresented = isPresented
        self.onClose = onClose
        self.content = content()
    }
    
    public var body: some View {
        if isPresented {
            ZStack {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation {
                            isPresented = false
                            onClose()
                        }
                    }
                
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text(title)
                            .font(.headline)
                        Spacer()
                        Button(action: {
                            withAnimation {
                                isPresented = false
                                onClose()
                            }
                        }) {
                            Image(systemName: "xmark")
                                .font(.title3)
                        }
                    }
                    .padding()
                    #if os(iOS)
                    .background(Color(uiColor: .systemGray6))
                    #else
                    .background(Color(NSColor.controlBackgroundColor))
                    #endif
                    
                    // Content
                    content
                        .padding()
                    
                    Spacer()
                }
                .frame(maxWidth: 600)
                    #if os(iOS)
                    .background(Color(uiColor: .systemBackground))
                    #else
                    .background(Color(NSColor.controlBackgroundColor))
                    #endif
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
                .padding()
                .transition(.scale.combined(with: .opacity))
            }
            .zIndex(1000)
        }
    }
}
