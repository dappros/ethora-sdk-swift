//
//  EditWrapperView.swift
//  XMPPChatUI
//
//  Edit mode wrapper
//

import SwiftUI
import XMPPChatCore

public struct EditWrapperView: View {
    let text: String
    let onClose: () -> Void
    let onSave: (String) -> Void
    
    @State private var editedText: String
    
    public init(
        text: String,
        onClose: @escaping () -> Void,
        onSave: @escaping (String) -> Void
    ) {
        self.text = text
        self.onClose = onClose
        self.onSave = onSave
        self._editedText = State(initialValue: text)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Editing message")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Cancel") {
                    onClose()
                }
                .font(.caption)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            #if os(iOS)
            .background(Color(uiColor: .systemGray6))
            #else
            .background(Color(NSColor.controlBackgroundColor))
            #endif
            
            HStack(spacing: 12) {
                if #available(iOS 16.0, macOS 13.0, *) {
                    TextField("Edit message", text: $editedText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...5)
                } else {
                    TextField("Edit message", text: $editedText)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(5)
                }
                
                Button(action: {
                    onSave(editedText)
                }) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(editedText.isEmpty ? .gray : .blue)
                }
                .disabled(editedText.isEmpty)
            }
            .padding()
            #if os(iOS)
        .background(Color(uiColor: .systemBackground))
        #else
        .background(Color(NSColor.controlBackgroundColor))
        #endif
        }
        .transition(.move(edge: .bottom))
    }
}
