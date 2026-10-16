//
//  CallOverlayView.swift
//  XMPPChatUI
//
//  App-level call screen: ringing cards (incoming, outgoing, error) and the
//  active call. Attached to ChatWrapperView, so an incoming call rings from any
//  screen. Translated from src/components/VideoCalls/VideoCallOverlay.tsx. The
//  web minimized floating panel is not implemented on iOS.
//

import SwiftUI
import XMPPChatCore

/// Overlay that shows the call screen while a call is active. Use `callOverlay(config:)`.
struct CallOverlayModifier: ViewModifier {
    @ObservedObject private var store: CallStore = .shared
    let config: VideoCallsConfig?

    func body(content: Content) -> some View {
        content.overlay {
            if store.state.phase != .idle {
                CallOverlayView(state: store.state, config: config)
            }
        }
    }
}

public extension View {
    /// Adds the app-level call overlay (incoming ring, outgoing ring, active call).
    /// Attach it to the chat root, e.g. `ChatWrapperView`. Off unless
    /// `config.videoCalls.enabled` is true.
    func callOverlay(config: VideoCallsConfig?) -> some View {
        modifier(CallOverlayModifier(config: config))
    }
}

struct CallOverlayView: View {
    let state: CallStore.State
    let config: VideoCallsConfig?

    private var livekitUrl: String {
        (config?.livekitUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The session is shown once a token exists and the call is connecting or in progress.
    private var showsSession: Bool {
        (state.phase == .connecting || state.phase == .inCall)
            && state.token != nil
            && !livekitUrl.isEmpty
    }

    private var kindWord: String {
        state.kind == .audio ? "audio" : "video"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(showsSession ? 1 : 0.6)
                .ignoresSafeArea()

            if showsSession, let token = state.token {
                ActiveCallView(
                    kind: state.kind,
                    url: livekitUrl,
                    token: token,
                    peerName: state.roomName ?? "",
                    startWithMicOn: config?.startWithMicOn ?? true,
                    startWithCameraOn: config?.startWithCameraOn ?? true
                )
                .id(state.callId ?? state.roomJid ?? token)
            } else {
                ringingContent
                    .padding(24)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var ringingContent: some View {
        switch state.phase {
        case .ringingIncoming:
            callCard(
                title: "Incoming \(kindWord) call",
                subtitle: state.kind == .audio ? "Audio call" : "Video call",
                roomName: state.roomName
            ) {
                circleButton(
                    systemImage: state.kind == .audio ? "phone.fill" : "video.fill",
                    tint: .green,
                    label: "Accept call"
                ) {
                    CallService.shared.acceptIncomingCall()
                }
                circleButton(systemImage: "phone.down.fill", tint: .red, label: "Decline call") {
                    CallService.shared.declineIncomingCall()
                }
            }

        case .error:
            callCard(
                title: "Call failed",
                subtitle: state.error ?? (livekitUrl.isEmpty ? "Video calls unavailable: missing livekitUrl in config.videoCalls" : "Please try again later"),
                roomName: state.roomName
            ) {
                Button("Dismiss") {
                    CallService.shared.dismissError()
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundColor(.black)
            }

        default:
            // Outgoing ring (requesting) and the short connecting gap before the session view.
            callCard(
                title: state.phase == .connecting ? "Connecting..." : "Calling...",
                subtitle: state.phase == .connecting
                    ? "Connecting to room"
                    : (state.kind == .audio ? "Audio call" : "Video call"),
                roomName: state.roomName
            ) {
                circleButton(systemImage: "phone.down.fill", tint: .red, label: "Cancel call") {
                    CallService.shared.hangUp()
                }
            }
        }
    }

    private func callCard<Actions: View>(
        title: String,
        subtitle: String,
        roomName: String?,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: 16) {
            Image(systemName: state.kind == .audio ? "phone.circle.fill" : "video.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.white.opacity(0.9))
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            if let roomName, !roomName.isEmpty {
                Text(roomName)
                    .font(.headline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            HStack(spacing: 32) {
                actions()
            }
            .padding(.top, 8)
        }
        .padding(28)
        .frame(maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(white: 0.12))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(roomName ?? "")")
    }

    private func circleButton(
        systemImage: String,
        tint: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 64, height: 64)
                .background(Circle().fill(tint))
        }
        .accessibilityLabel(label)
    }
}
