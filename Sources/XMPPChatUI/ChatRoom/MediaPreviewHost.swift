//
//  MediaPreviewHost.swift
//  XMPPChatUI
//
//  Single entry point for fullscreen media previews in chat. The previewer is picked once per file (by mime-type
//  or extension) and always renders a closable container. A multi-file message opens a pager over its files,
//  starting at the tapped one. Every URL carries the signed-in user's `ft` token for secure files.
//

import SwiftUI
import XMPPChatCore

struct MediaPreviewTarget: Identifiable {
    let id = UUID()
    let message: Message
    /// Index of the tapped file inside a multi-file message. 0 for single-file messages.
    var startIndex: Int = 0
}

struct MediaPreviewHost: View {
    let target: MediaPreviewTarget
    let onClose: () -> Void

    var body: some View {
        let items = target.message.mediaAttachments
        if items.count > 1 {
            MediaAlbumPager(items: items, startIndex: target.startIndex, onClose: onClose)
        } else {
            let message = target.message
            filePreview(
                location: message.location,
                fallbackLocation: message.locationPreview,
                mimeType: resolveMimeType(message),
                fileName: message.originalName ?? message.fileName ?? "File",
                onClose: onClose
            )
        }
    }

    private func resolveMimeType(_ message: Message) -> String {
        if let mt = message.mimetype?.trimmingCharacters(in: .whitespacesAndNewlines), !mt.isEmpty {
            return mt
        }
        if let location = message.location {
            return inferMimeType(from: location)
        }
        return "application/octet-stream"
    }

    @ViewBuilder
    fileprivate func filePreview(
        location: String?,
        fallbackLocation: String?,
        mimeType: String,
        fileName: String,
        onClose: @escaping () -> Void
    ) -> some View {
        if let url = SecureFileURL.currentURL(location) ?? SecureFileURL.currentURL(fallbackLocation) {
            switch mediaKind(for: mimeType, url: url) {
            case .image:
                FullScreenImageView(imageURL: url, onClose: onClose)
            case .video:
                #if os(iOS)
                FullScreenVideoView(videoURL: url, onClose: onClose)
                #else
                unsupportedFallback(message: "Video playback is available on iOS", onClose: onClose)
                #endif
            case .pdf:
                FullScreenPDFView(pdfURL: url, fileName: fileName, onClose: onClose)
            case .other:
                #if os(iOS)
                FullScreenFilePreview(fileURL: url, fileName: fileName, onClose: onClose)
                #else
                unsupportedFallback(message: "File preview is available on iOS", onClose: onClose)
                #endif
            }
        } else {
            unsupportedFallback(message: "Media URL is missing or invalid", onClose: onClose)
        }
    }
}

private enum MediaViewerKind { case image, video, pdf, other }

private func mediaKind(for mimeType: String, url: URL) -> MediaViewerKind {
    if mimeType.hasPrefix("image/") { return .image }
    if mimeType.hasPrefix("video/") { return .video }
    if mimeType.contains("pdf") { return .pdf }
    // Fall back to file extension when mimeType isn't informative.
    let ext = url.pathExtension.lowercased()
    if ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif"].contains(ext) { return .image }
    if ["mp4", "mov", "m4v"].contains(ext) { return .video }
    if ext == "pdf" { return .pdf }
    return .other
}

private func unsupportedFallback(message: String, onClose: @escaping () -> Void) -> some View {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 16) {
            Image(systemName: "doc")
                .font(.largeTitle)
                .foregroundColor(.white)
            Text("Can't open file")
                .foregroundColor(.white)
                .font(.headline)
            Text(message)
                .foregroundColor(.white.opacity(0.75))
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button(action: onClose) {
                Text("Close")
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(10)
            }
        }
    }
}

/// Pages across the files of a multi-file message. Each page is the same viewer a single file gets.
struct MediaAlbumPager: View {
    let items: [MessageAttachment]
    let onClose: () -> Void
    @State private var index: Int

    init(items: [MessageAttachment], startIndex: Int, onClose: @escaping () -> Void) {
        self.items = items
        self.onClose = onClose
        _index = State(initialValue: min(max(startIndex, 0), max(items.count - 1, 0)))
    }

    var body: some View {
        #if os(iOS)
        TabView(selection: $index) {
            ForEach(Array(items.enumerated()), id: \.offset) { position, item in
                MediaPageView(attachment: item, onClose: onClose)
                    .tag(position)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .background(Color.black.ignoresSafeArea())
        #else
        EmptyView()
        #endif
    }
}

private struct MediaPageView: View {
    let attachment: MessageAttachment
    let onClose: () -> Void

    var body: some View {
        let url = SecureFileURL.currentURL(attachment.location)
            ?? SecureFileURL.currentURL(attachment.locationPreview)
        if let url = url {
            switch mediaKind(for: attachment.effectiveMimetype, url: url) {
            case .image:
                FullScreenImageView(imageURL: url, onClose: onClose)
            case .video:
                #if os(iOS)
                FullScreenVideoView(videoURL: url, onClose: onClose)
                #else
                EmptyView()
                #endif
            case .pdf:
                FullScreenPDFView(pdfURL: url, fileName: attachment.displayName, onClose: onClose)
            case .other:
                #if os(iOS)
                FullScreenFilePreview(fileURL: url, fileName: attachment.displayName, onClose: onClose)
                #else
                EmptyView()
                #endif
            }
        } else {
            unsupportedFallback(message: "Media URL is missing or invalid", onClose: onClose)
        }
    }
}
