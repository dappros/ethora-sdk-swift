//
//  MediaPreviews.swift
//  XMPPChatUI
//

import SwiftUI
import XMPPChatCore
import AVKit

struct MediaMessagePreview: View {
    let message: Message
    let mimeType: String
    let isUser: Bool
    let onMediaTap: ((Message) -> Void)?
    
    var body: some View {
        Group {
            if mimeType.starts(with: "image/") {
                ImagePreview(
                    imageURL: message.location ?? "",
                    previewURL: message.locationPreview,
                    fileName: message.originalName ?? message.fileName ?? "Image",
                    onTap: { onMediaTap?(message) }
                )
            } else if mimeType.starts(with: "video/") {
                VideoPreview(
                    videoURL: message.location ?? "",
                    fileName: message.originalName ?? message.fileName ?? "Video",
                    onTap: { onMediaTap?(message) }
                )
            } else if mimeType.contains("pdf") {
                PDFPreview(
                    fileURL: message.location ?? "",
                    fileName: message.originalName ?? message.fileName ?? "Document.pdf",
                    size: message.size,
                    onTap: { onMediaTap?(message) }
                )
            } else {
                FilePreview(
                    fileURL: message.location ?? "",
                    fileName: message.originalName ?? message.fileName ?? "File",
                    mimeType: mimeType,
                    size: message.size,
                    previewURL: message.locationPreview,
                    onTap: { onMediaTap?(message) }
                )
            }
        }
    }
}

struct ImagePreview: View {
    let imageURL: String
    let previewURL: String?
    let fileName: String
    let onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onTap) {
                AsyncImage(url: URL(string: previewURL ?? imageURL)) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: 150, height: 200)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: 150, maxHeight: 200)
                .clipped()
                .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
            
            if !fileName.isEmpty {
                Text(fileName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct VideoPreview: View {
    let videoURL: String
    let fileName: String
    let onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onTap) {
                if let url = URL(string: videoURL) {
                    #if os(iOS)
                    VideoPlayer(player: AVPlayer(url: url))
                        .frame(width: 300, height: 200)
                        .cornerRadius(12)
                    #else
                    Text("Video preview")
                        .foregroundColor(.secondary)
                    #endif
                } else {
                    HStack {
                        Image(systemName: "video.fill")
                            .font(.largeTitle)
                            .foregroundColor(.blue)
                        Text(fileName)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            if !fileName.isEmpty {
                Text(fileName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct PDFPreview: View {
    let fileURL: String
    let fileName: String
    let size: String?
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "doc.fill")
                    .font(.largeTitle)
                    .foregroundColor(.red)
                VStack(alignment: .leading) {
                    Text(fileName)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if let size = size {
                        Text(formatFileSize(size))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct FilePreview: View {
    let fileURL: String
    let fileName: String
    let mimeType: String
    let size: String?
    let previewURL: String?
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                if let previewURL = previewURL, let url = URL(string: previewURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            Image(systemName: "doc.fill")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            Image(systemName: "doc.fill")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                        @unknown default:
                            Image(systemName: "doc.fill")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                        }
                    }
                    .frame(width: 100, height: 60)
                    .clipped()
                    .cornerRadius(8)
                } else {
                    Image(systemName: "doc.fill")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                        .frame(width: 100, height: 60)
                }
                
                VStack(alignment: .leading) {
                    Text(fileName)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if let size = size {
                        Text(formatFileSize(size))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
