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
    /// Sends an attachment. The optional third argument is the caption typed alongside
    /// the attachment — when non-empty it is delivered as a separate text message right
    /// after the media stanza.
    let onSendMedia: ((Data, String, String?) -> Void)?
    /// Sends every staged file in ONE message (an album) with the typed caption.
    /// When set, it is used instead of `onSendMedia` for the default composer.
    let onSendMediaFiles: (([OutgoingMediaFile], String?) -> Void)?
    /// `attachments` config: file count and per-file size limits.
    let attachmentsConfig: AttachmentsConfig?
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
        onSendMedia: ((Data, String, String?) -> Void)? = nil,
        onSendMediaFiles: (([OutgoingMediaFile], String?) -> Void)? = nil,
        attachmentsConfig: AttachmentsConfig? = nil,
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
        self.onSendMediaFiles = onSendMediaFiles
        self.attachmentsConfig = attachmentsConfig
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
                onSendMediaFiles: onSendMediaFiles,
                attachmentsConfig: attachmentsConfig,
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
    let onSendMedia: ((Data, String, String?) -> Void)?
    let onSendMediaFiles: (([OutgoingMediaFile], String?) -> Void)?
    let attachmentsConfig: AttachmentsConfig?
    let placeholderText: String
    let isEditing: Bool
    let editMessageId: String?
    let onCancelEdit: (() -> Void)?
    let disableMedia: Bool
    let secondarySendButton: SecondarySendButtonConfig?
    let messageTextFilter: MessageTextFilterConfig?
    
    @State private var showMediaPicker = false
    /// Files picked and waiting for Send. Sent together as one album.
    @State private var staged: [StagedMedia] = []
    @State private var attachmentNotice: String? = nil

    private var fileLimit: Int { (attachmentsConfig ?? AttachmentsConfig()).fileLimit }
    @FocusState private var isFocused: Bool
    
    private var inputSurfaceColor: Color {
        #if os(iOS)
        return Color(uiColor: .secondarySystemBackground)
        #else
        return Color(NSColor.controlBackgroundColor)
        #endif
    }
    
    private var iconForegroundColor: Color {
        #if os(iOS)
        return Color(uiColor: .label)
        #else
        return .primary
        #endif
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Staged files
            if !staged.isEmpty {
                StagedMediaStrip(items: staged, limit: fileLimit) { id in
                    staged.removeAll { $0.id == id }
                    attachmentNotice = nil
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            if let attachmentNotice {
                Text(attachmentNotice)
                    .font(.footnote)
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
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
                            .foregroundColor(iconForegroundColor)
                            .frame(width: 40, height: 40)
                            .background(inputSurfaceColor)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                            )
                    }
                    .accessibilityIdentifier(ChatInputAccessibilityID.attachButton)
                }
                
                ZStack(alignment: .leading) {
                    if messageText.isEmpty && staged.isEmpty {
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
                    .foregroundColor(.primary)
                }
                .background(inputSurfaceColor)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                )
                .accentColor(.blue)
                .focused($isFocused)
                .accessibilityIdentifier(ChatInputAccessibilityID.inputField)
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
                        sendMediaOrText()
                    }) {
                        if let label = secondaryButton.label {
                            AnyView(label)
                        } else {
                            AnyView(Text("Send"))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(ChatInputAccessibilityID.sendButton)
                } else {
                    Button(action: {
                        sendMediaOrText()
                    }) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background((messageText.isEmpty && staged.isEmpty) ? Color.gray : Color.blue)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                            )
                    }
                    .disabled(messageText.isEmpty && staged.isEmpty)
                    .accessibilityIdentifier(ChatInputAccessibilityID.sendButton)
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
            MediaPickerView(remainingSlots: max(1, fileLimit - staged.count), onMediaSelected: { files in
                stage(files)
            })
            .modifier(MediaPickerPresentationModifier())
        }
    }

    /// Adds picked files to the staging area, enforcing the file count and size limits.
    private func stage(_ files: [OutgoingMediaFile]) {
        var notice: String?
        var added = 0
        let sizeCap = (attachmentsConfig?.maxFileSizeMb).map { $0 * 1024 * 1024 }
        for file in files {
            if staged.count >= fileLimit {
                notice = "You can attach up to \(fileLimit) files per message."
                break
            }
            if let sizeCap, Double(file.data.count) > sizeCap {
                let name = file.fileName ?? "A file"
                notice = "\(name) is larger than \(Int(attachmentsConfig?.maxFileSizeMb ?? 0)) MB and was skipped."
                continue
            }
            #if os(iOS)
            let image: UIImage? = file.mimeType.hasPrefix("image/") ? UIImage(data: file.data) : nil
            staged.append(StagedMedia(file: file, image: image))
            #else
            staged.append(StagedMedia(file: file))
            #endif
            added += 1
        }
        attachmentNotice = notice
        if added > 0, notice == nil { attachmentNotice = nil }
    }
    
    private func sendMessage() {
        guard !messageText.isEmpty else { return }

        let textToSend = messageText
        messageText = ""
        onSendMessage(textToSend)
        HapticFeedback.messageSent()
    }

    /// If files are staged, send them together with the typed caption (if any) as ONE message.
    /// Otherwise fall back to a plain text send.
    private func sendMediaOrText() {
        guard !staged.isEmpty else {
            sendMessage()
            return
        }
        let trimmedCaption = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let caption: String? = trimmedCaption.isEmpty ? nil : messageText
        let files = staged.map(\.file)
        if let onSendMediaFiles {
            onSendMediaFiles(files, caption)
        } else if let onSendMedia {
            // Legacy single-file callback: one message per file, the caption goes with the first.
            for (index, file) in files.enumerated() {
                onSendMedia(file.data, file.mimeType, index == 0 ? caption : nil)
            }
        }
        messageText = ""
        staged = []
        attachmentNotice = nil
        HapticFeedback.messageSent()
    }
}

/// One file waiting in the composer.
struct StagedMedia: Identifiable {
    let id = UUID()
    let file: OutgoingMediaFile
    #if os(iOS)
    var image: UIImage? = nil
    #endif
}

/// Thumbnails of the staged files, each with a remove button.
struct StagedMediaStrip: View {
    let items: [StagedMedia]
    let limit: Int
    let onRemove: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        ZStack(alignment: .topTrailing) {
                            thumbnail(item)
                                .frame(width: 64, height: 64)
                                .background(Color.gray.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Button {
                                onRemove(item.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white)
                                    .background(Circle().fill(Color.black.opacity(0.6)))
                            }
                            .offset(x: 4, y: -4)
                            .accessibilityLabel("Remove attachment")
                        }
                        .padding(.top, 4)
                        .padding(.trailing, 4)
                    }
                }
            }
            if items.count > 1 {
                Text("\(items.count) of \(limit) files")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func thumbnail(_ item: StagedMedia) -> some View {
        #if os(iOS)
        if let image = item.image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            fallbackIcon(item)
        }
        #else
        fallbackIcon(item)
        #endif
    }

    private func fallbackIcon(_ item: StagedMedia) -> some View {
        VStack(spacing: 2) {
            Image(systemName: item.file.mimeType.hasPrefix("video/") ? "video.fill" : "doc.fill")
                .foregroundColor(.blue)
            if let name = item.file.fileName {
                Text(name).font(.system(size: 8)).lineLimit(1).padding(.horizontal, 2)
            }
        }
    }
}

struct MediaPickerView: View {
    /// How many more files the message can take; limits the library selection.
    let remainingSlots: Int
    let onMediaSelected: ([OutgoingMediaFile]) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var showImagePicker = false
    @State private var showDocumentPicker = false
    @State private var showCamera = false
    @State private var sourceType: UIImagePickerController.SourceType = .photoLibrary
    
    var body: some View {
        VStack(spacing: 0) {
            // Horizontal circular buttons
            HStack(spacing: 40) {
                Spacer()
                
                // Media (Photo Library)
                VStack(spacing: 8) {
                    Button(action: {
                        sourceType = .photoLibrary
                        showImagePicker = true
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.1))
                                .frame(width: 70, height: 70)
                            
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 28))
                                .foregroundColor(.blue)
                        }
                    }
                    Text("Media")
                        .font(.caption)
                        .foregroundColor(.primary)
                }
                
                // Camera
                VStack(spacing: 8) {
                    Button(action: {
                        sourceType = .camera
                        showCamera = true
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.1))
                                .frame(width: 70, height: 70)
                            
                            Image(systemName: "camera.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.blue)
                        }
                    }
                    Text("Camera")
                        .font(.caption)
                        .foregroundColor(.primary)
                }
                
                // File
                VStack(spacing: 8) {
                    Button(action: {
                        showDocumentPicker = true
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.1))
                                .frame(width: 70, height: 70)
                            
                            Image(systemName: "doc.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.blue)
                        }
                    }
                    Text("File")
                        .font(.caption)
                        .foregroundColor(.primary)
                }
                
                Spacer()
            }
            .padding(.vertical, 30)
            .padding(.top, 20)
        }
        .background(Color(uiColor: .systemBackground))
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(
                sourceType: sourceType,
                mediaTypes: ["public.image", "public.movie"],
                selectionLimit: remainingSlots,
                onMediaSelected: { _, _ in },
                onBatchSelected: { items in
                    onMediaSelected(items.map { OutgoingMediaFile(data: $0.0, mimeType: $0.1) })
                    dismiss()
                }
            )
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera, mediaTypes: ["public.image"], onMediaSelected: { data, mimeType in
                onMediaSelected([OutgoingMediaFile(data: data, mimeType: mimeType)])
                dismiss()
            })
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker(onDocumentsSelected: { picked in
                onMediaSelected(picked.prefix(remainingSlots).map {
                    OutgoingMediaFile(data: $0.0, mimeType: $0.2, fileName: $0.1)
                })
                dismiss()
            })
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
        #if os(iOS)
        .background(Color(uiColor: .secondarySystemBackground))
        #else
        .background(Color(NSColor.controlBackgroundColor))
        #endif
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

// MARK: - Test PDF Creator
#if os(iOS)
import PDFKit

func createTestPDF() -> Data? {
    let pdfMetaData = [
        kCGPDFContextCreator: "XMPP Chat App",
        kCGPDFContextAuthor: "Test User",
        kCGPDFContextTitle: "Test Document"
    ]
    let format = UIGraphicsPDFRendererFormat()
    format.documentInfo = pdfMetaData as [String: Any]
    
    let pageWidth = 8.5 * 72.0
    let pageHeight = 11 * 72.0
    let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
    
    let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
    
    let data = renderer.pdfData { (context) in
        context.beginPage()
        
        let titleFont = UIFont.boldSystemFont(ofSize: 24)
        let bodyFont = UIFont.systemFont(ofSize: 16)
        
        let titleText = "Test PDF Document"
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor.black
        ]
        let titleSize = titleText.size(withAttributes: titleAttributes)
        let titleRect = CGRect(
            x: (pageRect.width - titleSize.width) / 2,
            y: 100,
            width: titleSize.width,
            height: titleSize.height
        )
        titleText.draw(in: titleRect, withAttributes: titleAttributes)
        
        let bodyText = """
        This is a test PDF document created for testing file upload functionality.
        
        Created: \(Date().formatted(date: .abbreviated, time: .shortened))
        
        You can use this document to test:
        - PDF file upload
        - PDF file viewing
        - File sharing in chat
        
        Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.
        """
        
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: UIColor.black
        ]
        
        let bodyRect = CGRect(
            x: 72,
            y: 200,
            width: pageRect.width - 144,
            height: pageRect.height - 300
        )
        
        bodyText.draw(in: bodyRect, withAttributes: bodyAttributes)
    }
    
    return data
}
#endif

// MARK: - Media Picker Presentation Modifier
struct MediaPickerPresentationModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content
                .presentationDetents([.fraction(0.2)])
                .presentationDragIndicator(.visible)
        } else {
            content
        }
    }
}
