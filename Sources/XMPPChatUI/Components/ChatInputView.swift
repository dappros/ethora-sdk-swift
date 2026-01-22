//
//  ChatInputView.swift
//  XMPPChatUI
//
//  Chat input component with media, emoji, secondary button
//

import SwiftUI
import XMPPChatCore

public struct ConfigurableChatInputView: View {
    @Binding var messageText: String
    let onSendMessage: (String) -> Void
    let onSendMedia: ((Data, String) -> Void)?
    let placeholderText: String
    let isEditing: Bool
    let editMessageId: String?
    let onCancelEdit: (() -> Void)?
    let disableMedia: Bool
    let secondarySendButton: SecondarySendButtonConfig?
    let messageTextFilter: MessageTextFilterConfig?
    let customComponent: ((SendInputProps) -> AnyView)?
    
    @State private var showMediaPicker = false
    @State private var showEmojiPicker = false
    @FocusState private var isFocused: Bool
    
    public init(
        messageText: Binding<String>,
        onSendMessage: @escaping (String) -> Void,
        onSendMedia: ((Data, String) -> Void)? = nil,
        placeholderText: String = "Type a message...",
        isEditing: Bool = false,
        editMessageId: String? = nil,
        onCancelEdit: (() -> Void)? = nil,
        disableMedia: Bool = false,
        secondarySendButton: SecondarySendButtonConfig? = nil,
        messageTextFilter: MessageTextFilterConfig? = nil,
        customComponent: ((SendInputProps) -> AnyView)? = nil
    ) {
        self._messageText = messageText
        self.onSendMessage = onSendMessage
        self.onSendMedia = onSendMedia
        self.placeholderText = placeholderText
        self.isEditing = isEditing
        self.editMessageId = editMessageId
        self.onCancelEdit = onCancelEdit
        self.disableMedia = disableMedia
        self.secondarySendButton = secondarySendButton
        self.messageTextFilter = messageTextFilter
        self.customComponent = customComponent
    }
    
    public var body: some View {
        if let customComponent = customComponent {
            customComponent(SendInputProps(
                onSendMessage: onSendMessage,
                onSendMedia: onSendMedia,
                placeholderText: placeholderText,
                messageText: $messageText,
                isEditing: isEditing,
                editMessageId: editMessageId
            ))
        } else {
            DefaultChatInputView(
                messageText: $messageText,
                onSendMessage: onSendMessage,
                onSendMedia: onSendMedia,
                placeholderText: placeholderText,
                isEditing: isEditing,
                editMessageId: editMessageId,
                onCancelEdit: onCancelEdit,
                disableMedia: disableMedia,
                secondarySendButton: secondarySendButton,
                messageTextFilter: messageTextFilter
            )
        }
    }
}

struct DefaultChatInputView: View {
    @Binding var messageText: String
    let onSendMessage: (String) -> Void
    let onSendMedia: ((Data, String) -> Void)?
    let placeholderText: String
    let isEditing: Bool
    let editMessageId: String?
    let onCancelEdit: (() -> Void)?
    let disableMedia: Bool
    let secondarySendButton: SecondarySendButtonConfig?
    let messageTextFilter: MessageTextFilterConfig?
    
    @State private var showMediaPicker = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            if isEditing {
                Button("Cancel") {
                    onCancelEdit?()
                }
                .foregroundColor(.secondary)
                .padding(.trailing, 8)
            }
            
            if !disableMedia {
                Button(action: {
                    showMediaPicker = true
                }) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.black)
                        .frame(width: 40, height: 40)
                        .background(Color.white)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                        )
                }
            }
            
            ZStack(alignment: .leading) {
                if messageText.isEmpty {
                    Text(placeholderText)
                        .foregroundColor(.gray.opacity(0.6))
                        .padding(.horizontal, 16)
                }
                
                Group {
                    if #available(iOS 16.0, macOS 13.0, *) {
                        TextField("", text: $messageText, axis: .vertical)
                            .lineLimit(1...5)
                    } else {
                        TextField("", text: $messageText)
                            .lineLimit(5)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .foregroundColor(.black)
            }
            .background(Color.white)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
            )
            .accentColor(.blue)
            .focused($isFocused)
            .onSubmit {
                if !messageText.isEmpty {
                    sendMessage()
                }
            }
            .onChange(of: messageText) { newValue in
                if let filter = messageTextFilter, filter.enabled {
                    messageText = filter.filterFunction(newValue)
                }
            }
            
            if let secondaryButton = secondarySendButton, secondaryButton.enabled {
                Button(action: {
                    sendMessage()
                }) {
                    if let label = secondaryButton.label {
                        AnyView(label)
                    } else {
                        AnyView(Text("Send"))
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(action: {
                    sendMessage()
                }) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(messageText.isEmpty ? Color.gray : Color.blue)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                        )
                }
                .disabled(messageText.isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        #if os(iOS)
        .background(Color(uiColor: .systemBackground))
        #else
        .background(Color(NSColor.controlBackgroundColor))
        #endif
        .sheet(isPresented: $showMediaPicker) {
            MediaPickerView(onMediaSelected: { data, type in
                onSendMedia?(data, type)
            })
        }
    }
    
    private func sendMessage() {
        guard !messageText.isEmpty else { return }
        
        let textToSend = messageText
        messageText = ""
        onSendMessage(textToSend)
        HapticFeedback.messageSent()
    }
}

struct MediaPickerView: View {
    let onMediaSelected: (Data, String) -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Media Picker")
                    .font(.headline)
                // Implement media picker UI
                // For now, placeholder
            }
            .navigationTitle("Select Media")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}
