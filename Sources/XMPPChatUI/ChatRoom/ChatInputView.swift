//
//  ChatInputView.swift
//  XMPPChatUI
//

import SwiftUI

struct ChatInputView: View {
    @Binding var text: String
    let onSend: () -> Void
    let onSendMedia: (Data, String) -> Void
    let isEditing: Bool
    let editText: String?
    let onCancelEdit: () -> Void
    
    #if os(iOS)
    @State private var showImagePicker = false
    @State private var showDocumentPicker = false
    @State private var isRecordingAudio = false
    #endif
    
    var body: some View {
        VStack(spacing: 0) {
            if isEditing, let editText = editText {
                HStack {
                    Text("Editing: \(editText)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Cancel") {
                        onCancelEdit()
                    }
                    .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                #if os(iOS)
                .background(Color(uiColor: .systemGray6))
                #else
                .background(Color(NSColor.controlBackgroundColor))
                #endif
            }
            
            #if os(iOS)
            if isRecordingAudio {
                AudioRecorderView(
                    isRecording: $isRecordingAudio,
                    onAudioRecorded: { audioData, mimeType in
                        onSendMedia(audioData, mimeType)
                    },
                    onCancel: {
                        isRecordingAudio = false
                    }
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                inputView
            }
            #else
            inputView
            #endif
        }
        #if os(iOS)
        .animation(.easeInOut(duration: 0.3), value: isRecordingAudio)
        #endif
    }
    
    #if os(iOS)
    private var inputView: some View {
        HStack(spacing: 12) {
            Menu {
                Button(action: {
                    showImagePicker = true
                }) {
                    Label("Photo or Video", systemImage: "photo")
                }
                Button(action: {
                    showDocumentPicker = true
                }) {
                    Label("File", systemImage: "doc")
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(sourceType: .photoLibrary, mediaTypes: ["public.image", "public.movie"], onMediaSelected: { imageData, mimeType in
                    onSendMedia(imageData, mimeType)
                })
            }
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPicker(onDocumentSelected: { fileData, fileName, mimeType in
                    onSendMedia(fileData, mimeType)
                })
            }
            
            Button(action: {
                isRecordingAudio = true
            }) {
                Image(systemName: "mic.fill")
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.red)
                    .clipShape(Circle())
            }
            
            if #available(iOS 16.0, *) {
                TextField("Type a message", text: $text, axis: .vertical)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.96, green: 0.97, blue: 0.99))
                    .cornerRadius(12)
                    .lineLimit(1...5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(text.isEmpty ? Color.clear : Color.blue.opacity(0.3), lineWidth: 1)
                    )
            } else {
                TextField("Type a message", text: $text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.96, green: 0.97, blue: 0.99))
                    .cornerRadius(12)
                    .lineLimit(3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(text.isEmpty ? Color.clear : Color.blue.opacity(0.3), lineWidth: 1)
                    )
            }
            
            Button(action: {
                if !text.isEmpty {
                    onSend()
                }
            }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(text.isEmpty ? .gray : .blue)
            }
            .disabled(text.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(chatInputBackground())
        .cornerRadius(15, corners: [.topLeft, .topRight])
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: -2)
    }
    #else
    private var inputView: some View {
        HStack(spacing: 12) {
            Button(action: {
                // File picker for macOS
            }) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            
            TextField("Type a message", text: $text)
                .textFieldStyle(.roundedBorder)
            
            Button(action: {
                if !text.isEmpty {
                    onSend()
                }
            }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(text.isEmpty ? .gray : .blue)
            }
            .disabled(text.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    #endif
}
