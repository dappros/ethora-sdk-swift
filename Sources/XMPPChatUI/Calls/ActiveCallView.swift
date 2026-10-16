//
//  ActiveCallView.swift
//  XMPPChatUI
//
//  The live call screen: remote video, local preview, and the control bar
//  (mic, camera, flip, hang up). Audio calls show the peer name and no video.
//  Mirrors the controls in src/components/VideoCalls/VideoCallSession.tsx.
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

    @StateObject private var session = CallSessionController()

    var body: some View {
        ZStack {
            if kind == .video {
                videoStage
            } else {
                audioStage
            }

            VStack(spacing: 0) {
                if let message = session.deviceError {
                    deviceBanner(message)
                }
                Spacer()
                controlBar
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
        }
        .task {
            session.onPeerLeft = {
                CallService.shared.hangUp()
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
            Image(systemName: "person.circle.fill")
                .font(.system(size: 96))
                .foregroundColor(.white.opacity(0.85))
            Text(peerName)
                .font(.title2.weight(.semibold))
                .foregroundColor(.white)
            Text(session.isConnected ? "Audio call" : "Connecting...")
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

    // MARK: - Controls

    private var controlBar: some View {
        HStack(spacing: 20) {
            controlButton(
                systemImage: session.isMicrophoneOn ? "mic.fill" : "mic.slash.fill",
                label: session.isMicrophoneOn ? "Mute microphone" : "Unmute microphone"
            ) {
                Task { await session.toggleMicrophone() }
            }

            if kind == .video {
                controlButton(
                    systemImage: session.isCameraOn ? "video.fill" : "video.slash.fill",
                    label: session.isCameraOn ? "Turn camera off" : "Turn camera on"
                ) {
                    Task { await session.toggleCamera() }
                }

                if session.isCameraOn {
                    controlButton(systemImage: "arrow.triangle.2.circlepath.camera", label: "Flip camera") {
                        Task { await session.flipCamera() }
                    }
                }
            }

            controlButton(systemImage: "phone.down.fill", label: "End call", tint: .red) {
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

    private func controlButton(
        systemImage: String,
        label: String,
        tint: Color = Color.white.opacity(0.18),
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(tint))
        }
        .accessibilityLabel(label)
    }

    private func deviceBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(message)
                .font(.footnote)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                session.dismissDeviceError()
            } label: {
                Image(systemName: "xmark")
                    .foregroundColor(.white)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.red.opacity(0.9))
        )
        .padding(.top, 12)
    }
}
