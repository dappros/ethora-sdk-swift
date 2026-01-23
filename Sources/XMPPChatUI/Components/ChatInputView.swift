//
//  ChatInputView.swift
//  XMPPChatUI
//
//  Chat input component with media, emoji, secondary button
//

import SwiftUI
import XMPPChatCore
#if os(iOS)
import UIKit
#endif

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
    @State private var selectedMediaData: Data? = nil
    @State private var selectedMediaType: String? = nil
    @State private var selectedMediaFileName: String? = nil
    #if os(iOS)
    @State private var selectedMediaImage: UIImage? = nil
    #endif
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Media Preview
            if let mediaData = selectedMediaData, let mediaType = selectedMediaType {
                #if os(iOS)
                MediaPreviewView(
                    mediaData: mediaData,
                    mediaType: mediaType,
                    fileName: selectedMediaFileName,
                    image: selectedMediaImage,
                    onCancel: {
                        selectedMediaData = nil
                        selectedMediaType = nil
                        selectedMediaFileName = nil
                        selectedMediaImage = nil
                    }
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                #else
                MediaPreviewView(
                    mediaData: mediaData,
                    mediaType: mediaType,
                    fileName: selectedMediaFileName,
                    image: nil,
                    onCancel: {
                        selectedMediaData = nil
                        selectedMediaType = nil
                        selectedMediaFileName = nil
                    }
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                #endif
            }
            
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
                    if messageText.isEmpty && selectedMediaData == nil {
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
                        if selectedMediaData != nil {
                            // Send media
                            if let data = selectedMediaData, let type = selectedMediaType {
                                onSendMedia?(data, type)
                                selectedMediaData = nil
                                selectedMediaType = nil
                                selectedMediaFileName = nil
                                #if os(iOS)
                                selectedMediaImage = nil
                                #endif
                            }
                        } else {
                            sendMessage()
                        }
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
                        if selectedMediaData != nil {
                            // Send media
                            if let data = selectedMediaData, let type = selectedMediaType {
                                onSendMedia?(data, type)
                                selectedMediaData = nil
                                selectedMediaType = nil
                                selectedMediaFileName = nil
                                #if os(iOS)
                                selectedMediaImage = nil
                                #endif
                            }
                        } else {
                            sendMessage()
                        }
                    }) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background((messageText.isEmpty && selectedMediaData == nil) ? Color.gray : Color.blue)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                            )
                    }
                    .disabled(messageText.isEmpty && selectedMediaData == nil)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        #if os(iOS)
        .background(Color(uiColor: .systemBackground))
        #else
        .background(Color(NSColor.controlBackgroundColor))
        #endif
        .sheet(isPresented: $showMediaPicker) {
            MediaPickerView(onMediaSelected: { data, type, fileName in
                selectedMediaData = data
                selectedMediaType = type
                selectedMediaFileName = fileName
                #if os(iOS)
                if type.hasPrefix("image/"), let image = UIImage(data: data) {
                    selectedMediaImage = image
                }
                #endif
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
    let onMediaSelected: (Data, String, String?) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var showImagePicker = false
    @State private var showVideoPicker = false
    @State private var showDocumentPicker = false
    @State private var sourceType: UIImagePickerController.SourceType = .photoLibrary
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Photo option
                Button(action: {
                    sourceType = .photoLibrary
                    showImagePicker = true
                }) {
                    HStack {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundColor(.blue)
                        Text("Photo")
                            .font(.headline)
                        Spacer()
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                }
                
                // Video option
                Button(action: {
                    sourceType = .photoLibrary
                    showVideoPicker = true
                }) {
                    HStack {
                        Image(systemName: "video")
                            .font(.title2)
                            .foregroundColor(.blue)
                        Text("Video")
                            .font(.headline)
                        Spacer()
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                }
                
                // File option
                Button(action: {
                    showDocumentPicker = true
                }) {
                    HStack {
                        Image(systemName: "doc")
                            .font(.title2)
                            .foregroundColor(.blue)
                        Text("File")
                            .font(.headline)
                        Spacer()
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                }
                
                Spacer()
            }
            .padding()
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
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(sourceType: sourceType, mediaTypes: ["public.image"], onMediaSelected: { data, mimeType in
                    onMediaSelected(data, mimeType, nil)
                    dismiss()
                })
            }
            .sheet(isPresented: $showVideoPicker) {
                ImagePicker(sourceType: sourceType, mediaTypes: ["public.movie"], onMediaSelected: { data, mimeType in
                    onMediaSelected(data, mimeType, nil)
                    dismiss()
                })
            }
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPicker(onDocumentSelected: { fileData, fileName, mimeType in
                    onMediaSelected(fileData, mimeType, fileName)
                    dismiss()
                })
            }
        }
    }
}

// MARK: - Media Preview View
struct MediaPreviewView: View {
    let mediaData: Data
    let mediaType: String
    let fileName: String?
    #if os(iOS)
    let image: UIImage?
    #else
    let image: Any? = nil
    #endif
    let onCancel: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Preview
            Group {
                if mediaType.hasPrefix("image/") {
                    #if os(iOS)
                    if let uiImage = image {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                    }
                    #else
                    Image(systemName: "photo")
                        .foregroundColor(.gray)
                    #endif
                } else if mediaType.hasPrefix("video/") {
                    Image(systemName: "video.fill")
                        .foregroundColor(.blue)
                } else {
                    Image(systemName: "doc.fill")
                        .foregroundColor(.blue)
                }
            }
            .frame(width: 60, height: 60)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .clipped()
            
            // File info
            VStack(alignment: .leading, spacing: 4) {
                if let fileName = fileName {
                    Text(fileName)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                } else {
                    Text(mediaType.hasPrefix("image/") ? "Image" : mediaType.hasPrefix("video/") ? "Video" : "File")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }
                
                Text(formatFileSize(mediaData.count))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Cancel button
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.gray)
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
        )
    }
    
    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
