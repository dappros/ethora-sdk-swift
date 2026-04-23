//
//  MediaPreviewHost.swift
//  XMPPChatUI
//
//  Единая точка входа для fullscreen-превью медиа в чате. Раньше в
//  ChatRoomView жили три отдельных `.fullScreenCover`/`.sheet` с пустыми
//  ветками `if let url = URL(string:)`, из-за чего при невалидной ссылке
//  показывался чёрный экран без кнопки закрытия. Теперь превью выбирается
//  ровно один раз (по mime-type/расширению файла) и всегда рендерит
//  закрываемый контейнер — либо нужный просмотрщик, либо понятный fallback.
//

import SwiftUI
import XMPPChatCore

struct MediaPreviewTarget: Identifiable {
    let id = UUID()
    let message: Message
}

struct MediaPreviewHost: View {
    let target: MediaPreviewTarget
    let onClose: () -> Void

    var body: some View {
        let message = target.message
        let url = resolveURL(message.location) ?? resolveURL(message.locationPreview)
        let mimeType = resolveMimeType(message)
        let fileName = message.originalName ?? message.fileName ?? "File"

        if let url = url {
            switch kind(for: mimeType, url: url) {
            case .image:
                FullScreenImageView(imageURL: url, onClose: onClose)
            case .video:
                #if os(iOS)
                FullScreenVideoView(videoURL: url, onClose: onClose)
                #else
                unsupportedFallback(message: "Video playback is available on iOS")
                #endif
            case .pdf:
                FullScreenPDFView(pdfURL: url, fileName: fileName, onClose: onClose)
            case .other:
                #if os(iOS)
                FullScreenFilePreview(fileURL: url, fileName: fileName, onClose: onClose)
                #else
                unsupportedFallback(message: "File preview is available on iOS")
                #endif
            }
        } else {
            unsupportedFallback(message: "Media URL is missing or invalid")
        }
    }

    private enum Kind { case image, video, pdf, other }

    private func kind(for mimeType: String, url: URL) -> Kind {
        if mimeType.hasPrefix("image/") { return .image }
        if mimeType.hasPrefix("video/") { return .video }
        if mimeType.contains("pdf") { return .pdf }
        // Fallback по расширению, если mimeType не информативный.
        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif"].contains(ext) { return .image }
        if ["mp4", "mov", "m4v"].contains(ext) { return .video }
        if ext == "pdf" { return .pdf }
        return .other
    }

    private func resolveURL(_ raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let direct = URL(string: raw), direct.scheme != nil {
            return direct
        }
        if let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let encodedURL = URL(string: encoded),
           encodedURL.scheme != nil {
            return encodedURL
        }
        return nil
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

    private func unsupportedFallback(message: String) -> some View {
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
}
