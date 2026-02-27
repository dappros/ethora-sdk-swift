//
//  ChatRoomModals.swift
//  XMPPChatUI
//

import SwiftUI
import XMPPChatCore
import WebKit

// MARK: - File Preview Modal
struct FilePreviewModal: View {
    let message: Message
    let onClose: () -> Void
    
    @State private var isDownloading = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let mimeType = message.mimetype, let fileURL = message.location, let url = URL(string: fileURL) {
                    Group {
                        if mimeType.starts(with: "image/") {
                            FullScreenImageView(imageURL: url, onClose: onClose)
                        } else if mimeType.starts(with: "video/") {
                            #if os(iOS)
                            FullScreenVideoView(videoURL: url, onClose: onClose)
                            #else
                            Text("Video playback not available on macOS")
                                .foregroundColor(.secondary)
                            #endif
                        } else if mimeType.contains("pdf") {
                            FullScreenPDFView(pdfURL: url, fileName: message.originalName ?? message.fileName ?? "Document.pdf", onClose: onClose)
                        } else {
                            UnsupportedFileView(
                                fileURL: fileURL,
                                fileName: message.originalName ?? message.fileName ?? "File",
                                mimeType: mimeType
                            )
                        }
                    }
                } else {
                    Text("Unable to load file")
                        .foregroundColor(.white)
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        onClose()
                    }
                    .foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: downloadFile) {
                        if isDownloading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.white)
                        }
                    }
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onClose()
                    }
                    .foregroundColor(.white)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: downloadFile) {
                        if isDownloading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.white)
                        }
                    }
                }
                #endif
            }
        }
    }
    
    private func downloadFile() {
        guard let fileURL = message.location, let url = URL(string: fileURL) else { return }
        
        isDownloading = true
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                
                #if os(iOS)
                if let mimeType = message.mimetype, mimeType.starts(with: "image/") {
                    if let image = UIImage(data: data) {
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    }
                } else if let mimeType = message.mimetype, mimeType.starts(with: "video/") {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    try data.write(to: tempURL)
                } else {
                    let fileName = message.originalName ?? message.fileName ?? "file"
                    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let filePath = documentsPath.appendingPathComponent(fileName)
                    try data.write(to: filePath)
                }
                #endif
                
                isDownloading = false
            } catch {
                isDownloading = false
            }
        }
    }
}

// MARK: - PDF Viewer View
struct PDFViewerView: View {
    let pdfURL: String
    
    var body: some View {
        #if os(iOS)
        if let url = URL(string: pdfURL) {
            WebView(url: url)
        } else {
            Text("Unable to load PDF")
                .foregroundColor(.white)
        }
        #else
        Text("PDF viewer not implemented for macOS")
            .foregroundColor(.white)
        #endif
    }
}

// MARK: - Unsupported File View
struct UnsupportedFileView: View {
    let fileURL: String
    let fileName: String
    let mimeType: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.fill")
                .font(.system(size: 100))
                .foregroundColor(.white)
            
            VStack(spacing: 8) {
                Text("Unable to open the uploaded document")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("The file format is not supported by the system. Please upload a file in a compatible format. You still can download this file.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(16)
        }
    }
}

// MARK: - WebView for PDF (iOS only)
#if os(iOS)
struct WebView: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
    }
}
#endif
