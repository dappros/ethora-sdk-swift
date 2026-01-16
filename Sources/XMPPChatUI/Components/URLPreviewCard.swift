//
//  URLPreviewCard.swift
//  XMPPChatUI
//
//  URL preview card component
//

import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import XMPPChatCore

public struct URLPreviewCard: View {
    let url: String
    let isUserMessage: Bool
    
    @State private var previewData: URLPreviewData?
    @State private var isLoading: Bool = true
    @State private var error: String?
    
    public init(url: String, isUserMessage: Bool) {
        self.url = url
        self.isUserMessage = isUserMessage
    }
    
    public var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(height: 100)
            } else if let data = previewData {
                previewCard(data: data)
            }
        }
        .onAppear {
            fetchPreview()
        }
    }
    
    private func previewCard(data: URLPreviewData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let imageURL = data.image, let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                }
                .frame(height: 120)
                .cornerRadius(4)
            }
            
            if let title = data.title {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }
            
            if let description = data.description {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
            
            Text(hostname)
                .font(.caption2)
                .foregroundColor(.secondary)
                .underline()
        }
        .padding(8)
        .background(Color.white)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .onTapGesture {
            if let url = URL(string: url) {
                #if os(iOS)
                UIApplication.shared.open(url)
                #elseif os(macOS)
                NSWorkspace.shared.open(url)
                #endif
            }
        }
    }
    
    private var hostname: String {
        if let url = URL(string: url) {
            return url.host ?? url.absoluteString
        }
        return url
    }
    
    private func fetchPreview() {
        guard url.hasPrefix("http://") || url.hasPrefix("https://") else {
            isLoading = false
            return
        }
        
        // Using linkpreview.net API (free tier available)
        // In production, you should use your own API key
        let apiKey = "55b9e7f85f2b4e94505e96ef71c55a0e" // Replace with your API key
        guard let apiURL = URL(string: "https://api.linkpreview.net/?key=\(apiKey)&q=\(url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") else {
            isLoading = false
            return
        }
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: apiURL)
                let response = try JSONDecoder().decode(LinkPreviewResponse.self, from: data)
                
                await MainActor.run {
                    if let title = response.title, let description = response.description {
                        previewData = URLPreviewData(
                            title: title,
                            description: description,
                            image: response.image
                        )
                    }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

struct URLPreviewData {
    let title: String?
    let description: String?
    let image: String?
}

struct LinkPreviewResponse: Codable {
    let title: String?
    let description: String?
    let image: String?
}

// MARK: - URL Detection Helper
public extension String {
    func extractURLs() -> [String] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: self, options: [], range: NSRange(location: 0, length: self.utf16.count))
        return matches?.compactMap { match in
            guard let range = Range(match.range, in: self) else { return nil }
            return String(self[range])
        } ?? []
    }
}
