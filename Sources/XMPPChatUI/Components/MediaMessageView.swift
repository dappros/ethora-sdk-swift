//
//  MediaMessageView.swift
//  XMPPChatUI
//
//  Media message display component
//

import SwiftUI
import AVKit
import Combine
import XMPPChatCore

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
    @State private var duration: TimeInterval = 0
    @State private var currentTime: TimeInterval = 0
    @State private var timeObserver: Any?
    @State private var cancellables = Set<AnyCancellable>()
    @State private var waveformData: [Float]?
    @State private var progress: Double = 0
    
    var body: some View {
        HStack(spacing: 12) {
            // Play/Pause button
            Button(action: {
                togglePlayback()
            }) {
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .offset(x: isPlaying ? 0 : 2)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                // Real waveform
                if let location = message.location, let url = URL(string: location) {
                    AudioWaveformView(
                        audioURL: url,
                        waveformData: waveformData,
                        waveColor: Color.blue.opacity(0.3),
                        progressColor: Color.blue,
                        onSeek: { seekProgress in
                            if let player = player, duration > 0 {
                                let time = CMTime(seconds: duration * seekProgress, preferredTimescale: 600)
                                player.seek(to: time)
                            }
                        }
                    )
                }
                
                // Time info
                HStack {
                    Text(formatTime(currentTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if duration > 0 {
                        Text("/ \(formatTime(duration))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(red: 0.95, green: 0.97, blue: 0.99))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        .onAppear {
            setupPlayer()
            loadWaveformData()
        }
        .onDisappear {
            cleanupPlayer()
        }
        .onChange(of: currentTime) { newValue in
            if duration > 0 {
                progress = newValue / duration
            }
        }
    }
    
    private func setupPlayer() {
        guard let location = message.location, let url = URL(string: location) else { return }
        
        player = AVPlayer(url: url)
        
        // Observe duration
        player?.currentItem?.publisher(for: \.duration)
            .sink { [self] durationValue in
                if durationValue.isValid && !durationValue.isIndefinite {
                    self.duration = durationValue.seconds
                }
            }
            .store(in: &cancellables)
        
        // Observe time updates
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [self] time in
            currentTime = time.seconds
            if currentTime >= duration && duration > 0 {
                isPlaying = false
            }
        }
    }
    
    private func cleanupPlayer() {
        player?.pause()
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        cancellables.removeAll()
        player = nil
    }
    
    private func togglePlayback() {
        guard let player = player else { return }
        
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }
    
    private func loadWaveformData() {
        // Try to load waveform from message.waveForm if available
        // Otherwise, AudioWaveformView will generate it from audio
        if let waveForm = message.waveForm, !waveForm.isEmpty {
            // Parse waveform data if it's a string representation
            // This depends on the format from the server
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
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
