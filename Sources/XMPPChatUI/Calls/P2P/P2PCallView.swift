//
//  P2PCallView.swift
//  XMPPChatUI
//
//  Active screen of a peer to peer call: remote video, a small self view and
//  the mic / camera / hang-up controls. Mirrors
//  src/components/VideoCalls/P2PCallSession.tsx (minimal layout).
//

import LiveKitWebRTC
import SwiftUI
import XMPPChatCore

/// Renders a WebRTC video track.
struct P2PVideoView: UIViewRepresentable {
    let track: LKRTCVideoTrack?
    var mirror = false

    final class Coordinator {
        var track: LKRTCVideoTrack?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> LKRTCMTLVideoView {
        let view = LKRTCMTLVideoView(frame: .zero)
        view.videoContentMode = .scaleAspectFill
        view.transform = mirror ? CGAffineTransform(scaleX: -1, y: 1) : .identity
        return view
    }

    func updateUIView(_ view: LKRTCMTLVideoView, context: Context) {
        view.transform = mirror ? CGAffineTransform(scaleX: -1, y: 1) : .identity
        let coordinator = context.coordinator
        if coordinator.track !== track {
            coordinator.track?.remove(view)
            track?.add(view)
            coordinator.track = track
        }
    }

    static func dismantleUIView(_ view: LKRTCMTLVideoView, coordinator: Coordinator) {
        coordinator.track?.remove(view)
        coordinator.track = nil
    }
}

struct P2PCallView: View {
    @ObservedObject var controller: P2PCallController
    let peerName: String
    var connectedAt: Date?
    var onMinimize: (() -> Void)?

    private var statusText: String {
        switch controller.status {
        case .preparing: return "Starting..."
        case .waiting: return "Ringing..."
        case .connecting: return "Connecting..."
        case .connected: return ""
        case .reconnecting: return "Reconnecting..."
        case .failed, .ended: return "Call ended"
        }
    }

    private var showsRemoteVideo: Bool {
        controller.kind == .video && controller.remoteVideoTrack != nil && controller.remoteVideoLive
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if showsRemoteVideo {
                P2PVideoView(track: controller.remoteVideoTrack)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 12) {
                    CallAvatar(name: peerName, size: 96)
                    if !peerName.isEmpty {
                        Text(peerName).font(.title2.weight(.semibold)).foregroundColor(.white)
                    }
                    HStack(spacing: 6) {
                        if !statusText.isEmpty { Text(statusText) }
                        if controller.status == .connected {
                            Text(controller.kind == .audio ? "Audio call" : "Video call")
                            CallTimerText(since: connectedAt)
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.75))
                }
            }

            VStack {
                HStack(alignment: .top) {
                    if showsRemoteVideo {
                        // Over video the name and timer sit in the corner.
                        VStack(alignment: .leading, spacing: 2) {
                            Text(peerName).font(.subheadline.weight(.semibold))
                            HStack(spacing: 6) {
                                if !statusText.isEmpty { Text(statusText) }
                                CallTimerText(since: connectedAt)
                            }
                            .font(.caption)
                        }
                        .foregroundColor(.white)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.45)))
                    }
                    Spacer()
                    if let onMinimize {
                        CallMinimizeButton(action: onMinimize)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                if controller.status == .reconnecting {
                    Text("Reconnecting...")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.orange.opacity(0.9)))
                        .padding(.top, 8)
                }

                HStack {
                    Spacer()
                    if controller.localVideoTrack != nil {
                        P2PVideoView(track: controller.localVideoTrack, mirror: controller.frontCamera)
                            .frame(width: 110, height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
                            )
                            .padding(16)
                            .accessibilityLabel("Your camera preview")
                    }
                }
                if let notice = controller.notice {
                    CallDeviceBanner(message: notice) { controller.dismissNotice() }
                        .padding(.horizontal, 16)
                }
                Spacer()
                controls
                    .padding(.bottom, 24)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var controls: some View {
        HStack(spacing: 16) {
            CallControlButton(
                systemImage: controller.micEnabled ? "mic.fill" : "mic.slash.fill",
                label: controller.micEnabled ? "Mute microphone" : "Unmute microphone"
            ) {
                controller.toggleMic()
            }
            if controller.kind == .video {
                CallControlButton(
                    systemImage: controller.camEnabled ? "video.fill" : "video.slash.fill",
                    label: controller.camEnabled ? "Turn camera off" : "Turn camera on"
                ) {
                    Task { await controller.toggleCamera() }
                }
                if controller.camEnabled {
                    CallControlButton(systemImage: "arrow.triangle.2.circlepath.camera", label: "Flip camera") {
                        Task { await controller.flipCamera() }
                    }
                }
            }
            CallControlButton(
                systemImage: controller.speakerOn ? "speaker.wave.2.fill" : "speaker.fill",
                label: controller.speakerOn ? "Use receiver" : "Use speaker"
            ) {
                controller.toggleSpeaker()
            }
            CallControlButton(systemImage: "phone.down.fill", label: "End call", tint: .red) {
                CallService.shared.hangUp()
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(Capsule(style: .continuous).fill(Color.black.opacity(0.55)))
    }
}
