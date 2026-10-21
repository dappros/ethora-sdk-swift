//
//  ActiveCallView.swift
//  XMPPChatUI
//
//  The live LiveKit call screen: remote video, local preview, and the control
//  bar (mic, camera, flip, speaker, hang up). Audio calls show the peer name
//  and no video. Group calls show everyone in a grid with the speaking
//  participant highlighted and a mic-off badge per tile. Mirrors
//  src/components/VideoCalls/VideoCallSession.tsx.
//

import SwiftUI
import LiveKit
import XMPPChatCore

struct ActiveCallView: View {
    let kind: CallKind
    let url: String
    let token: String
    let peerName: String
    let startWithMicOn: Bool
    let startWithCameraOn: Bool
    var isGroup = false
    var connectedAt: Date?
    var onMinimize: (() -> Void)?

    @StateObject private var session = CallSessionController()

    var body: some View {
        ZStack {
            if isGroup {
                groupStage
            } else if kind == .video {
                videoStage
            } else {
                audioStage
            }

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if let onMinimize {
                        CallMinimizeButton(action: onMinimize)
                    }
                }
                .padding(.top, 8)
                if let message = session.deviceError {
                    CallDeviceBanner(message: message) { session.dismissDeviceError() }
                }
                Spacer()
                controlBar
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
        }
        .task {
            session.isGroup = isGroup
            if !isGroup {
                session.onPeerLeft = {
                    CallService.shared.hangUp()
                }
            }
            await session.connect(
                url: url,
                token: token,
                kind: kind,
                startWithMicOn: startWithMicOn,
                startWithCameraOn: startWithCameraOn
            )
        }
        .onDisappear {
            Task { await session.disconnect() }
        }
    }

    // MARK: - Stages

    private var videoStage: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let remote = session.remoteVideoTrack {
                    SwiftUIVideoView(remote, layoutMode: .fill)
                } else {
                    placeholder(text: peerName.isEmpty ? "Waiting for the other side..." : "Waiting for \(peerName)...")
                }
            }
            .ignoresSafeArea()

            if let local = session.localVideoTrack {
                SwiftUIVideoView(local, layoutMode: .fill, mirrorMode: .mirror)
                    .frame(width: 110, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.4), lineWidth: 1)
                    )
                    .padding(16)
                    .padding(.bottom, 96)
                    .accessibilityLabel("Your camera preview")
            }
        }
    }

    private var audioStage: some View {
        VStack(spacing: 12) {
            CallAvatar(name: peerName, size: 96)
            Text(peerName)
                .font(.title2.weight(.semibold))
                .foregroundColor(.white)
            HStack(spacing: 6) {
                Text(session.isConnected ? "Audio call" : "Connecting...")
                if session.isConnected { CallTimerText(since: connectedAt) }
            }
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.7))
        }
    }

    private func placeholder(text: String) -> some View {
        ZStack {
            Color(white: 0.1)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding()
        }
    }

    // MARK: - Group grid

    private var groupStatus: String {
        if !session.isConnected { return "Connecting..." }
        if session.tiles.count <= 1 { return "Waiting for others..." }
        return "\(session.tiles.count) participants"
    }

    private var groupStage: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                Text(peerName.isEmpty ? (kind == .video ? "Group video call" : "Group audio call") : peerName)
                    .font(.headline)
                    .foregroundColor(.white)
                HStack(spacing: 6) {
                    Text(groupStatus)
                    if session.tiles.count > 1 { CallTimerText(since: connectedAt) }
                }
                .font(.footnote)
                .foregroundColor(.white.opacity(0.7))
            }
            .padding(.top, 14)
            .padding(.horizontal, 56)

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: kind == .video ? 150 : 130), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(groupTiles) { tile in
                        participantTile(tile)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 110)
            }
        }
    }

    /// Screen shares become their own tile next to the participant's camera.
    private var groupTiles: [GroupTile] {
        session.tiles.flatMap { tile -> [GroupTile] in
            var items = [GroupTile(id: tile.id, source: tile, screen: false)]
            if kind == .video, tile.screen != nil {
                items.insert(GroupTile(id: tile.id + ":screen", source: tile, screen: true), at: 0)
            }
            return items
        }
    }

    private struct GroupTile: Identifiable {
        let id: String
        let source: CallParticipantTile
        let screen: Bool
    }

    private func participantTile(_ item: GroupTile) -> some View {
        let tile = item.source
        let track = item.screen ? tile.screen : (kind == .video ? tile.camera : nil)
        return ZStack(alignment: .bottomLeading) {
            Color(white: 0.1)
            if let track {
                SwiftUIVideoView(
                    track,
                    layoutMode: item.screen ? .fit : .fill,
                    mirrorMode: tile.isLocal && !item.screen ? .mirror : .off
                )
            } else {
                CallAvatar(name: tile.name, size: 64)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 6) {
                if tile.micMuted && !item.screen { CallMicOffBadge() }
                Text((tile.isLocal && tile.name != "You" ? "\(tile.name) (You)" : tile.name) + (item.screen ? " - screen" : ""))
                    .font(.footnote)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.black.opacity(0.5)))
            .padding(8)
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    tile.speaking && !item.screen ? Color(red: 0, green: 0.32, blue: 0.8) : Color.white.opacity(0.12),
                    lineWidth: tile.speaking && !item.screen ? 3 : 1
                )
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack(spacing: 16) {
            CallControlButton(
                systemImage: session.isMicrophoneOn ? "mic.fill" : "mic.slash.fill",
                label: session.isMicrophoneOn ? "Mute microphone" : "Unmute microphone"
            ) {
                Task { await session.toggleMicrophone() }
            }

            if kind == .video {
                CallControlButton(
                    systemImage: session.isCameraOn ? "video.fill" : "video.slash.fill",
                    label: session.isCameraOn ? "Turn camera off" : "Turn camera on"
                ) {
                    Task { await session.toggleCamera() }
                }

                if session.isCameraOn {
                    CallControlButton(systemImage: "arrow.triangle.2.circlepath.camera", label: "Flip camera") {
                        Task { await session.flipCamera() }
                    }
                }
            }

            CallControlButton(
                systemImage: session.isSpeakerOn ? "speaker.wave.2.fill" : "speaker.fill",
                label: session.isSpeakerOn ? "Use receiver" : "Use speaker"
            ) {
                session.toggleSpeaker()
            }

            CallControlButton(systemImage: "phone.down.fill", label: isGroup ? "Leave call" : "End call", tint: .red) {
                CallService.shared.hangUp()
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.55))
        )
    }
}
