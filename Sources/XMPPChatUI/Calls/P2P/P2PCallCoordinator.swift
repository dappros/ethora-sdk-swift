//
//  P2PCallCoordinator.swift
//  XMPPChatUI
//
//  Headless owner of the p2p controller for the call in CallStore. It builds
//  the controller when a p2p call needs one, wires its events back into the
//  call state and the server reports, and releases it on EVERY way a call can
//  stop (the phase goes idle or error, the call changes), which is what keeps
//  the microphone, the camera and the peer connection from leaking.
//  Mirrors src/components/VideoCalls/P2PCallRunner.tsx.
//
//    caller: the controller exists from the moment the create response says
//            `p2p` and starts at once (media, offer);
//    callee: the controller exists while the incoming call rings, so the
//            caller's offer / candidates / cancel are caught, but it only
//            starts (media, answer) after the user accepts.
//

import AVFoundation
import Combine
import Foundation
import LiveKitWebRTC
import XMPPChatCore

@MainActor
public final class P2PCallCoordinator: ObservableObject {
    public static let shared = P2PCallCoordinator()

    /// The live controller for the current p2p call, if any.
    @Published public private(set) var controller: P2PCallController?

    private var activeCallId: String?
    private var detachInbox: (() -> Void)?
    private var startedCallId: String?
    private var cancellable: AnyCancellable?

    private init() {}

    /// Begins following the call state. Idempotent; the call overlay calls it.
    public func start() {
        guard cancellable == nil else { return }
        // With CallKit the system owns the audio session; WebRTC must be told when
        // it is activated (see P2PCallController.useCallKitAudio).
        CallMediaControls.shared.audioSessionDidActivate = { session in
            let rtc = LKRTCAudioSession.sharedInstance()
            guard rtc.useManualAudio else { return }
            rtc.audioSessionDidActivate(session)
            rtc.isAudioEnabled = true
        }
        CallMediaControls.shared.audioSessionDidDeactivate = { session in
            let rtc = LKRTCAudioSession.sharedInstance()
            guard rtc.useManualAudio else { return }
            rtc.isAudioEnabled = false
            rtc.audioSessionDidDeactivate(session)
        }
        cancellable = CallStore.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.reconcile(state)
            }
        reconcile(CallStore.shared.state)
    }

    private func reconcile(_ state: CallStore.State) {
        let enabled = ConfigStore.shared.config.videoCalls?.enabled == true
        let callId = (state.callId ?? "")
        let isIncoming = state.direction == .incoming
        let wants: Bool
        if !enabled || state.mode != .p2p || callId.isEmpty {
            wants = false
        } else if isIncoming {
            wants = [.ringingIncoming, .connecting, .inCall].contains(state.phase)
        } else {
            wants = state.direction == .outgoing
                && state.iceServers != nil
                && [.requesting, .connecting, .inCall].contains(state.phase)
        }

        guard wants else {
            release()
            return
        }
        // The callee waits on the ring screen; everyone else starts right away.
        let shouldStart = !(isIncoming && state.phase == .ringingIncoming)

        if activeCallId != callId {
            release()
            guard let peer = state.peerXmppUsername, !peer.isEmpty else {
                // Without the peer's address there is nobody to signal.
                CallStore.shared.setCallError("Cannot reach the other participant")
                return
            }
            create(callId: callId, peer: peer, state: state)
        }
        if shouldStart, startedCallId != callId, let controller {
            startedCallId = callId
            Task { await controller.start() }
        }
    }

    private func create(callId: String, peer: String, state: CallStore.State) {
        let role: P2PRole = state.direction == .incoming ? .callee : .caller
        let videoCalls = ConfigStore.shared.config.videoCalls

        var events = P2PCallController.Events()
        events.onNegotiated = {
            if role == .caller, Self.isCurrent(callId) { CallStore.shared.markNegotiated() }
        }
        events.onConnected = {
            guard Self.isCurrent(callId) else { return }
            CallStore.shared.markConnected()
            // One side is enough to start the server-side call timer.
            if role == .caller {
                CallsAPI.fireAndForget { await CallsAPI.reportCallState(.connected, callId: callId) }
            }
        }
        events.onRemoteEnd = { reason in
            guard Self.isCurrent(callId) else { return }
            if let notice = P2PCallController.remoteEndNotice(reason) {
                CallStore.shared.setCallError(notice)
            } else {
                CallStore.shared.resetCall()
            }
        }
        events.onFailed = { message in
            if Self.isCurrent(callId) { CallStore.shared.setCallError(message) }
        }
        // Whatever ended it, tell the server the call is over (idempotent, so it
        // does not matter that the peer reports it too). A callee that never
        // accepted ends through the decline report instead.
        events.onDisposed = { started in
            if started { CallsAPI.fireAndForget { await CallsAPI.reportCallState(.end, callId: callId) } }
        }

        let controller = P2PCallController(
            params: P2PCallController.Params(
                callId: callId,
                role: role,
                kind: state.kind,
                peerXmppUsername: peer,
                iceServers: state.iceServers ?? [],
                startWithMicOn: videoCalls?.startWithMicOn ?? true,
                startWithCameraOn: videoCalls?.startWithCameraOn ?? true
            ),
            events: events
        )
        detachInbox = P2PRuntime.shared.inbox.attach(callId: callId) { [weak controller] signal in
            controller?.receive(signal)
        }
        activeCallId = callId
        startedCallId = nil
        self.controller = controller
    }

    private func release() {
        guard activeCallId != nil || controller != nil else { return }
        let released = controller
        detachInbox?()
        detachInbox = nil
        activeCallId = nil
        startedCallId = nil
        controller = nil
        released?.dispose()
    }

    private static func isCurrent(_ callId: String) -> Bool {
        let current = CallStore.shared.state
        return current.phase != .idle && current.callId == callId
    }
}
