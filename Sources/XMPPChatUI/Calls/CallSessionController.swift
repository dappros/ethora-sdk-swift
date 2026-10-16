//
//  CallSessionController.swift
//  XMPPChatUI
//
//  Owns one LiveKit Room for one call: connects with the call-token, publishes
//  the microphone and camera, and exposes what the call screen needs.
//  Translated from the connect and device handling in
//  src/components/VideoCalls/VideoCallSession.tsx.
//

import Foundation
import Combine
import LiveKit
import XMPPChatCore

@MainActor
final class CallSessionController: ObservableObject {
    @Published private(set) var remoteVideoTrack: VideoTrack?
    @Published private(set) var localVideoTrack: VideoTrack?
    @Published private(set) var isMicrophoneOn = false
    @Published private(set) var isCameraOn = false
    /// Camera or microphone problem. Shown as a dismissible hint. It never ends the call.
    @Published private(set) var deviceError: String?
    @Published private(set) var isConnected = false
    /// Connection failure that ends the call (bad token, network).
    @Published private(set) var connectError: String?

    /// Fired once, when the remote side leaves after having joined.
    var onPeerLeft: (() -> Void)?

    private let room: LiveKit.Room
    private let events: RoomEvents
    private var hasHadRemoteParticipant = false
    private var peerLeftFired = false

    init() {
        let roomOptions = RoomOptions(
            defaultVideoPublishOptions: VideoPublishOptions(simulcast: true),
            adaptiveStream: true,
            dynacast: true
        )
        room = LiveKit.Room(roomOptions: roomOptions)
        events = RoomEvents()
        events.owner = self
        room.delegates.add(delegate: events)
    }

    // MARK: - Connect

    /// Connects once. Media is best-effort after connect: a denied camera or
    /// microphone shows `deviceError` and the call continues.
    func connect(
        url: String,
        token: String,
        kind: CallKind,
        startWithMicOn: Bool,
        startWithCameraOn: Bool
    ) async {
        // Video calls use the loudspeaker, audio calls use the receiver (web parity).
        AudioManager.shared.isSpeakerOutputPreferred = kind == .video

        do {
            try await room.connect(
                url: url,
                token: token,
                connectOptions: ConnectOptions(autoSubscribe: true)
            )
        } catch {
            connectError = error.localizedDescription
            CallStore.shared.setCallError(error.localizedDescription)
            return
        }

        do {
            try await room.localParticipant.setMicrophone(enabled: startWithMicOn)
        } catch {
            deviceError = Self.humanize(error)
        }
        if kind == .video {
            do {
                try await room.localParticipant.setCamera(enabled: startWithCameraOn)
            } catch {
                deviceError = Self.humanize(error)
            }
        }

        isConnected = true
        refreshState()
        CallStore.shared.markConnected()
    }

    /// Leaves the room. Suppresses the peer-left callback, since this side hung up.
    func disconnect() async {
        peerLeftFired = true
        await room.disconnect()
        isConnected = false
    }

    // MARK: - Controls

    func toggleMicrophone() async {
        do {
            try await room.localParticipant.setMicrophone(enabled: !isMicrophoneOn)
        } catch {
            deviceError = Self.humanize(error)
        }
        refreshState()
    }

    func toggleCamera() async {
        do {
            try await room.localParticipant.setCamera(enabled: !isCameraOn)
        } catch {
            deviceError = Self.humanize(error)
        }
        refreshState()
    }

    /// Switches between the front and back camera. Not on web, which has no
    /// flip control. Added for mobile.
    func flipCamera() async {
        guard let localTrack = room.localParticipant.localVideoTracks
            .compactMap({ $0.track as? LocalVideoTrack })
            .first,
              let capturer = localTrack.capturer as? CameraCapturer else {
            return
        }
        do {
            _ = try await capturer.switchCameraPosition()
        } catch {
            deviceError = Self.humanize(error)
        }
    }

    func dismissDeviceError() {
        deviceError = nil
    }

    // MARK: - State

    fileprivate func refreshState() {
        let local = room.localParticipant
        isMicrophoneOn = local.isMicrophoneEnabled()
        isCameraOn = local.isCameraEnabled()
        localVideoTrack = local.videoTracks
            .first { $0.source == .camera }?
            .track as? VideoTrack

        let remote = room.remoteParticipants.values.first
        remoteVideoTrack = remote?.videoTracks
            .first { $0.source == .camera }?
            .track as? VideoTrack

        if remote != nil {
            hasHadRemoteParticipant = true
        } else if hasHadRemoteParticipant, !peerLeftFired {
            peerLeftFired = true
            onPeerLeft?()
        }
    }

    private static func humanize(_ error: Error) -> String {
        let text = error.localizedDescription.lowercased()
        if text.contains("permission") || text.contains("denied") {
            return "Camera or microphone permission denied. Allow access in Settings to use it."
        }
        if text.contains("not found") || text.contains("no device") {
            return "No camera or microphone found on this device."
        }
        if text.contains("in use") {
            return "Your camera or microphone is already in use by another app."
        }
        return "Could not access your camera or microphone."
    }
}

// MARK: - LiveKit room delegate bridge

/// LiveKit delegates are Objective-C protocols, so this bridge is an NSObject.
/// Callbacks hop to the main actor before touching the controller.
private final class RoomEvents: NSObject, RoomDelegate, @unchecked Sendable {
    weak var owner: CallSessionController?

    func roomDidConnect(_ room: LiveKit.Room) {
        notify()
    }

    func room(_ room: LiveKit.Room, participantDidConnect participant: RemoteParticipant) {
        notify()
    }

    func room(_ room: LiveKit.Room, participantDidDisconnect participant: RemoteParticipant) {
        notify()
    }

    func room(_ room: LiveKit.Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        notify()
    }

    func room(_ room: LiveKit.Room, participant: RemoteParticipant, didUnsubscribeTrack publication: RemoteTrackPublication) {
        notify()
    }

    func room(_ room: LiveKit.Room, participant: LocalParticipant, didPublishTrack publication: LocalTrackPublication) {
        notify()
    }

    func room(_ room: LiveKit.Room, participant: LocalParticipant, didUnpublishTrack publication: LocalTrackPublication) {
        notify()
    }

    func room(_ room: LiveKit.Room, didDisconnectWithError error: LiveKitError?) {
        notify()
    }

    private func notify() {
        Task { @MainActor [weak self] in
            self?.owner?.refreshState()
        }
    }
}
