//
//  VideoPlayerView.swift
//  XMPPChatUI
//
//  Enhanced video player with controls
//

import SwiftUI
import AVKit

public struct VideoPlayerView: View {
    let url: URL
    @State private var player: AVPlayer?
    @State private var isPlaying: Bool = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isFullScreen: Bool = false
    
    public init(url: URL) {
        self.url = url
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            if let player = player {
                VideoPlayer(player: player)
                    .frame(height: 200)
                    .onAppear {
                        setupPlayer()
                    }
                    .onDisappear {
                        player.pause()
                    }
                
                // Custom Controls
                HStack(spacing: 16) {
                    Button(action: {
                        if isPlaying {
                            player.pause()
                        } else {
                            player.play()
                        }
                        isPlaying.toggle()
                    }) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title2)
                    }
                    
                    Text(formatTime(currentTime))
                        .font(.caption)
                        .monospacedDigit()
                    
                    Slider(value: $currentTime, in: 0...duration) { editing in
                        if !editing {
                            let time = CMTime(seconds: currentTime, preferredTimescale: 600)
                            player.seek(to: time)
                        }
                    }
                    
                    Text(formatTime(duration))
                        .font(.caption)
                        .monospacedDigit()
                    
                    Button(action: {
                        isFullScreen.toggle()
                    }) {
                        Image(systemName: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.caption)
                    }
                }
                .padding()
                .background(Color.black.opacity(0.7))
            } else {
                ProgressView()
                    .frame(height: 200)
            }
        }
        .cornerRadius(12)
    }
    
    private func setupPlayer() {
        player = AVPlayer(url: url)
        
        // Observe time
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        _ = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            currentTime = time.seconds
            if let duration = player?.currentItem?.duration, duration.isValid {
                self.duration = duration.seconds
            }
        }
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
