//
//  MediaMessageView.swift
//  XMPPChatUI
//
//  Media message display component
//

import SwiftUI
import AVKit

public struct MediaMessageView: View {
    let message: Message
    let isUser: Bool
    
    public init(message: Message, isUser: Bool) {
        self.message = message
        self.isUser = isUser
    }
    
    public var body: some View {
        Group {
            if let mimetype = message.mimetype {
                switch mimetype {
                case let mime where mime.hasPrefix("image/"):
                    ImageMessageView(message: message)
                case let mime where mime.hasPrefix("video/"):
                    VideoMessageView(message: message)
                case let mime where mime.hasPrefix("audio/"):
                    AudioMessageView(message: message)
                default:
                    FileMessageView(message: message)
                }
            } else {
                FileMessageView(message: message)
            }
        }
    }
}

struct ImageMessageView: View {
    let message: Message
    @State private var image: Image?
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if let location = message.location, let url = URL(string: location) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: 200, height: 200)
                    case .success(let img):
                        img
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 250, maxHeight: 250)
                            .cornerRadius(12)
                    case .failure:
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else if let locationPreview = message.locationPreview, let url = URL(string: locationPreview) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let img):
                        img
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 250, maxHeight: 250)
                            .cornerRadius(12)
                    case .failure:
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Image(systemName: "photo")
                    .foregroundColor(.gray)
            }
        }
    }
}

struct VideoMessageView: View {
    let message: Message
    @State private var player: AVPlayer?
    
    var body: some View {
        Group {
            if let location = message.location, let url = URL(string: location) {
                VideoPlayer(player: player)
                    .frame(height: 200)
                    .cornerRadius(12)
                    .onAppear {
                        player = AVPlayer(url: url)
                    }
            } else {
                Image(systemName: "video")
                    .foregroundColor(.gray)
            }
        }
    }
}

struct AudioMessageView: View {
    let message: Message
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    
    var body: some View {
        HStack {
            Button(action: {
                if isPlaying {
                    player?.pause()
                } else {
                    player?.play()
                }
                isPlaying.toggle()
            }) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .foregroundColor(.blue)
            }
            
            if let fileName = message.fileName {
                Text(fileName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
        .onAppear {
            if let location = message.location, let url = URL(string: location) {
                player = AVPlayer(url: url)
            }
        }
    }
}

struct FileMessageView: View {
    let message: Message
    
    var body: some View {
        HStack {
            Image(systemName: "doc.fill")
                .font(.title2)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                if let fileName = message.fileName ?? message.originalName {
                    Text(fileName)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }
                
                if let size = message.size {
                    Text(size)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button(action: {
                // Download file
                if let location = message.location, let url = URL(string: location) {
                    #if os(iOS)
                    UIApplication.shared.open(url)
                    #elseif os(macOS)
                    NSWorkspace.shared.open(url)
                    #endif
                }
            }) {
                Image(systemName: "arrow.down.circle")
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}
