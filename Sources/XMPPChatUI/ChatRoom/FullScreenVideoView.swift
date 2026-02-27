//
//  FullScreenVideoView.swift
//  XMPPChatUI
//

import SwiftUI
import AVKit

#if os(iOS)
struct FullScreenVideoView: View {
    let videoURL: URL
    let onClose: () -> Void
    @State private var player: AVPlayer?
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear {
                        player.play()
                    }
            } else {
                ProgressView()
                    .tint(.white)
                    .onAppear {
                        player = AVPlayer(url: videoURL)
                    }
            }
            
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        player?.pause()
                        onClose()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding()
                    }
                }
                Spacer()
            }
        }
    }
}
#endif
