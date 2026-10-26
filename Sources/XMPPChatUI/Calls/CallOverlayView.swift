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
    @ObservedObject private var p2p: P2PCallCoordinator = .shared
    #if canImport(CallKit)
    @ObservedObject private var callKit: CallKitBridge = .shared
    #endif
    @State private var minimized = false
    let config: VideoCallsConfig?

    func body(content: Content) -> some View {
        content
            .onAppear { P2PCallCoordinator.shared.start() }
            // Every call starts expanded.
            .onChange(of: store.state.callId) { _ in minimized = false }
            .onChange(of: store.state.phase) { phase in
                if phase == .idle || phase == .error || phase == .ringingIncoming { minimized = false }
            }
            .overlay {
                if store.state.phase != .idle && !systemRingHandlesCall {
                    CallOverlayView(
                        state: store.state,
                        config: config,
                        p2pController: p2p.controller,
                        minimized: $minimized
                    )
                }
            }
    }
}

extension CallOverlayModifier {
    /// With CallKit on, the system UI rings for an incoming call, so the in-app card stays hidden.
    fileprivate var systemRingHandlesCall: Bool {
        #if canImport(CallKit)
        return store.state.phase == .ringingIncoming && callKit.handlesRinging(for: store.state.callId)
        #else
        return false
        #endif
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
    /// Controller of the current peer to peer call, nil for LiveKit calls.
    var p2pController: P2PCallController?
    /// The active call shrunk to a strip (the media session stays mounted).
    @Binding var minimized: Bool

    /// The URL the system account sent on the call-token wins over the host config.
    private var livekitUrl: String {
        let fromCall = (state.livekitUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !fromCall.isEmpty { return fromCall }
        return (config?.livekitUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A p2p call is shown once its controller exists and the call is connecting
    /// or in progress.
    private var showsP2PSession: Bool {
        state.mode == .p2p
            && (state.phase == .connecting || state.phase == .inCall)
            && p2pController != nil
    }

    /// The LiveKit session is shown once a token exists and the call is
    /// connecting or in progress.
    private var showsSession: Bool {
        state.mode != .p2p
            && (state.phase == .connecting || state.phase == .inCall)
            && state.token != nil
            && !livekitUrl.isEmpty
    }

    private var kindWord: String {
        let base = state.kind == .audio ? "audio" : "video"
        return state.isGroup ? "group \(base)" : base
    }

    private var sessionVisible: Bool { showsSession || showsP2PSession }

    var body: some View {
        ZStack(alignment: .top) {
            if !(sessionVisible && minimized) {
                Color.black.opacity(sessionVisible ? 1 : 0.6)
                    .ignoresSafeArea()
            }

            if sessionVisible {
                sessionContent
                    // Minimized: keep the session alive but invisible; the strip
                    // below is the only thing on screen.
                    .frame(
                        width: minimized ? 1 : nil,
                        height: minimized ? 1 : nil
                    )
                    .opacity(minimized ? 0.01 : 1)
                    .allowsHitTesting(!minimized)
                    .clipped()

                if minimized {
                    CallMinimizedStrip(
                        title: state.roomName ?? "",
                        subtitle: state.phase == .inCall ? (state.kind == .audio ? "Audio" : "Video") : "Connecting...",
                        connectedAt: state.connectedAt,
                        onExpand: { minimized = false },
                        onHangup: { CallService.shared.hangUp() }
                    )
                }
            } else {
                ringingContent
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var sessionContent: some View {
        if showsP2PSession, let p2pController {
            P2PCallView(
                controller: p2pController,
                peerName: state.roomName ?? "",
                connectedAt: state.connectedAt,
                onMinimize: { minimized = true }
            )
            .id(state.callId ?? state.roomJid ?? "p2p")
        } else if let token = state.token {
            ActiveCallView(
                kind: state.kind,
                url: livekitUrl,
                token: token,
                peerName: state.roomName ?? "",
                startWithMicOn: config?.startWithMicOn ?? true,
                startWithCameraOn: config?.startWithCameraOn ?? true,
                isGroup: state.isGroup,
                connectedAt: state.connectedAt,
                onMinimize: { minimized = true }
            )
            .id(state.callId ?? state.roomJid ?? token)
        }
    }

    /// "<person> is calling in <room>" for a group once both are known.
    private var incomingSubtitle: String {
        let noun = state.kind == .audio ? "Audio call" : "Video call"
        let label = state.isGroup ? "Group \(noun.lowercased())" : noun
        if state.isGroup, let caller = state.callerName, !caller.isEmpty,
           let room = state.roomName, !room.isEmpty {
            return "\(caller) is calling in \(room)"
        }
        return label
    }

    @ViewBuilder
    private var ringingContent: some View {
        switch state.phase {
        case .ringingIncoming:
            callCard(
                title: "Incoming \(kindWord) call",
                subtitle: incomingSubtitle,
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
            Text((roomName ?? "").isEmpty ? (state.direction == .incoming ? "Incoming call" : "Call") : roomName!)
                .font(.headline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
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
