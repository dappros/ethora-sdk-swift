//
//  P2PCallController.swift
//  XMPPChatUI
//
//  One peer to peer call, from microphone/camera capture to hang-up, on top of
//  the WebRTC build that the LiveKit Swift SDK already links (LiveKitWebRTC),
//  so no second WebRTC binary ships. The decisions live in the pure Core
//  modules (P2PNegotiator, IceRestartPolicy, P2PSignalCodec); this class only
//  wires them to a real LKRTCPeerConnection and cleans up after itself.
//  Mirrors src/calls/p2p/P2PCallController.ts.
//
//  Media encryption: a peer connection already encrypts media between the two
//  peers with DTLS-SRTP, so the LiveKit E2EE layer is deliberately NOT applied
//  on this path.
//

import AVFoundation
import Foundation
import LiveKitWebRTC
import XMPPChatCore

/// Owns the shared peer connection factory (encoder/decoder factories are
/// expensive to build, one is enough for the process).
enum P2PWebRTC {
    static let factory: LKRTCPeerConnectionFactory = {
        LKRTCPeerConnectionFactory(
            encoderFactory: LKRTCDefaultVideoEncoderFactory(),
            decoderFactory: LKRTCDefaultVideoDecoderFactory()
        )
    }()
}

/// Forwards peer connection callbacks (WebRTC signalling thread) to closures.
private final class P2PPeerDelegate: NSObject, LKRTCPeerConnectionDelegate {
    var onCandidate: ((P2PCandidatePayload) -> Void)?
    var onConnectionState: ((P2PConnState) -> Void)?
    var onIceState: ((LKRTCIceConnectionState) -> Void)?
    var onRemoteVideo: ((LKRTCVideoTrack) -> Void)?

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange stateChanged: LKRTCSignalingState) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didAdd stream: LKRTCMediaStream) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didRemove stream: LKRTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: LKRTCPeerConnection) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange newState: LKRTCIceGatheringState) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didRemove candidates: [LKRTCIceCandidate]) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didOpen dataChannel: LKRTCDataChannel) {}

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange newState: LKRTCIceConnectionState) {
        onIceState?(newState)
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange newState: LKRTCPeerConnectionState) {
        let mapped: P2PConnState
        switch newState {
        case .new: mapped = .new
        case .connecting: mapped = .connecting
        case .connected: mapped = .connected
        case .disconnected: mapped = .disconnected
        case .failed: mapped = .failed
        case .closed: mapped = .closed
        @unknown default: mapped = .new
        }
        onConnectionState?(mapped)
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didGenerate candidate: LKRTCIceCandidate) {
        guard !candidate.sdp.isEmpty else { return }
        onCandidate?(P2PCandidatePayload(
            candidate: candidate.sdp,
            sdpMid: candidate.sdpMid,
            sdpMLineIndex: Int(candidate.sdpMLineIndex)
        ))
    }

    func peerConnection(
        _ peerConnection: LKRTCPeerConnection,
        didAdd rtpReceiver: LKRTCRtpReceiver,
        streams mediaStreams: [LKRTCMediaStream]
    ) {
        if let video = rtpReceiver.track as? LKRTCVideoTrack {
            onRemoteVideo?(video)
        }
    }
}

/// Notes when the last remote video frame arrived, so the UI can tell a camera
/// that was turned off (no frames) from a live one.
final class P2PFrameWatcher: NSObject, LKRTCVideoRenderer {
    private let lock = NSLock()
    private var last: Date?

    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: LKRTCVideoFrame?) {
        lock.lock()
        last = Date()
        lock.unlock()
    }

    var hasRecentFrame: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let last else { return false }
        return Date().timeIntervalSince(last) < 2
    }
}

@MainActor
public final class P2PCallController: ObservableObject {
    public enum Status: Equatable {
        case preparing, waiting, connecting, connected, reconnecting, failed, ended
    }

    public struct Params {
        public var callId: String
        public var role: P2PRole
        public var kind: CallKind
        /// Peer's xmpp username; signals from anyone else are ignored.
        public var peerXmppUsername: String
        public var iceServers: [IceServerConfig]
        public var startWithMicOn: Bool
        public var startWithCameraOn: Bool
    }

    /// Callbacks into the call state. All run on the main actor.
    public struct Events {
        /// The offer/answer exchange completed: media is now negotiating.
        public var onNegotiated: () -> Void = {}
        /// Media is flowing for the first time.
        public var onConnected: () -> Void = {}
        /// The peer ended the call (hang up, decline, their own failure).
        public var onRemoteEnd: (String) -> Void = { _ in }
        /// The call failed locally; the message is meant for the user.
        public var onFailed: (String) -> Void = { _ in }
        /// Called exactly once when resources are released. `started` is false
        /// for a callee that never accepted.
        public var onDisposed: (Bool) -> Void = { _ in }
    }

    @Published public private(set) var status: Status = .preparing
    @Published public private(set) var micEnabled: Bool
    @Published public private(set) var camEnabled: Bool
    @Published public private(set) var localVideoTrack: LKRTCVideoTrack?
    @Published public private(set) var remoteVideoTrack: LKRTCVideoTrack?
    /// The peer's camera is sending frames right now (false when they turned it off).
    @Published public private(set) var remoteVideoLive = false
    @Published public private(set) var speakerOn: Bool
    @Published public private(set) var frontCamera = true
    /// Dismissible, non-fatal hint (e.g. the camera could not be started).
    @Published public private(set) var notice: String?

    public let callId: String
    public let role: P2PRole
    public let kind: CallKind

    private let params: Params
    private let events: Events
    private let negotiator: P2PNegotiator
    private var policy = IceRestartPolicy()

    private let peerDelegate = P2PPeerDelegate()
    private let frameWatcher = P2PFrameWatcher()
    private var watchedTrack: LKRTCVideoTrack?
    private var liveTimer: Task<Void, Never>?
    private var cameraDevicePosition: AVCaptureDevice.Position = .front
    private var pc: LKRTCPeerConnection?
    private var audioTrack: LKRTCAudioTrack?
    private var videoSource: LKRTCVideoSource?
    private var capturer: LKRTCCameraVideoCapturer?
    private var videoSender: LKRTCRtpSender?

    private var queue: Task<Void, Never> = Task {}
    private var timers: [Task<Void, Never>] = []
    private var graceTimer: Task<Void, Never>?
    private var deadlineTimer: Task<Void, Never>?
    private var connectTimer: Task<Void, Never>?

    private var started = false
    private var disposed = false
    private var endSent = false
    private var connectedOnce = false
    private var negotiated = false
    private var cameraBusy = false
    private var lastConn: P2PConnState?

    // Outgoing candidates wait until the offer/answer they belong to is out.
    private var candidateGateOpen = false
    private var heldOutgoingCandidates: [P2PCandidatePayload] = []
    private var sentCandidates: [P2PCandidatePayload] = []
    private var lastOffer: String?

    private static let connectTimeout: TimeInterval = 25
    private static let offerResend: [TimeInterval] = [4, 10]

    public init(params: Params, events: Events) {
        self.params = params
        self.events = events
        self.callId = params.callId
        self.role = params.role
        self.kind = params.kind
        self.negotiator = P2PNegotiator(
            callId: params.callId,
            role: params.role,
            peerLocal: params.peerXmppUsername
        )
        self.micEnabled = params.startWithMicOn
        self.camEnabled = params.kind == .video && params.startWithCameraOn
        // Video calls use the loudspeaker, audio calls the receiver (web parity).
        self.speakerOn = params.kind == .video
    }

    private func log(_ message: String) {
        NSLog("[p2p %@] %@", callId, message)
    }

    // MARK: - Lifecycle

    /// Caller: get media, build the connection, offer. Callee: get media, build
    /// the connection, then apply the offer that may already be waiting. Safe to
    /// call once; every failure ends the call with a message instead of throwing.
    public func start() async {
        if started || disposed { return }
        started = true
        status = .preparing

        // Credentials are fetched while the permission prompt is open.
        let given = params.iceServers
        let iceTask = Task { () -> [IceServerConfig] in
            if !given.isEmpty { return given }
            return await CallsAPI.fetchIceServers()?.iceServers ?? []
        }

        do {
            try await acquireMedia()
        } catch {
            log("media failed: \(error)")
            iceTask.cancel()
            fail(Self.describeMediaError(error), reason: "media-error")
            return
        }
        if disposed {
            releaseMedia()
            return
        }

        let servers = await iceTask.value
        if disposed { return }

        guard createConnection(servers: servers) else {
            fail("Could not start the call", reason: "setup-error")
            return
        }

        enqueue { [weak self] in
            guard let self else { return }
            try await self.runCommands(self.negotiator.markReady())
            if self.role == .caller, !self.disposed {
                try await self.sendOffer(iceRestart: false)
                self.status = .waiting
                self.scheduleOfferResends()
            }
        }
    }

    /// Feed a signal from the peer (already routed by callId).
    public func receive(_ signal: P2PSignal) {
        if disposed { return }
        let commands = negotiator.receive(signal)
        // An end must act immediately: it can arrive while the permission
        // prompt is still open, before the job queue is running.
        for command in commands {
            if case let .remoteEnd(reason) = command {
                handleRemoteEnd(reason)
                return
            }
        }
        if !commands.isEmpty {
            enqueue { [weak self] in try await self?.runCommands(commands) }
        }
    }

    /// Local user hung up (or cancelled): tell the peer and release everything.
    public func hangup(reason: String = "hangup") {
        if disposed { return }
        sendEnd(reason)
        dispose()
    }

    /// Releases every resource: timers, tracks, the connection. Idempotent.
    /// Tells the peer unless it is already known to be over.
    public func dispose() {
        if disposed { return }
        disposed = true
        if started, !negotiator.isEnded { sendEnd("hangup") }

        timers.forEach { $0.cancel() }
        timers.removeAll()
        graceTimer?.cancel()
        deadlineTimer?.cancel()
        connectTimer?.cancel()
        negotiator.stop()

        peerDelegate.onCandidate = nil
        peerDelegate.onConnectionState = nil
        peerDelegate.onIceState = nil
        peerDelegate.onRemoteVideo = nil
        pc?.delegate = nil
        pc?.close()
        pc = nil
        releaseMedia()

        liveTimer?.cancel()
        watchedTrack?.remove(frameWatcher)
        watchedTrack = nil
        remoteVideoTrack = nil
        remoteVideoLive = false
        if status != .failed { status = .ended }
        events.onDisposed(started)
    }

    private func sendEnd(_ reason: String) {
        if endSent { return }
        endSent = true
        P2PRuntime.shared.send(
            peerXmppUsername: params.peerXmppUsername,
            callId: callId,
            signal: .end,
            payload: .end(reason: reason)
        )
    }

    private func fail(_ message: String, reason: String) {
        if disposed { return }
        sendEnd(reason)
        status = .failed
        notice = message
        events.onFailed(message)
        dispose()
    }

    private func handleRemoteEnd(_ reason: String) {
        if disposed { return }
        endSent = true // the peer already knows
        status = .ended
        events.onRemoteEnd(reason)
        dispose()
    }

    /// What to show when the PEER ended the call for a failure rather than a
    /// normal hang up / decline. Nil means "just close the call".
    public static func remoteEndNotice(_ reason: String) -> String? {
        switch reason {
        case "media-error":
            return "The other person could not access their camera or microphone"
        case "connect-timeout", "connection-failed", "negotiation-error", "setup-error":
            return "The call could not be connected"
        default:
            return nil
        }
    }

    // MARK: - Media

    private enum MediaError: Error {
        case micDenied
        case cameraDenied
    }

    private static func describeMediaError(_ error: Error) -> String {
        switch error as? MediaError {
        case .micDenied, .cameraDenied:
            return "Camera or microphone permission denied"
        case nil:
            return "Could not access your camera or microphone"
        }
    }

    private func acquireMedia() async throws {
        let micGranted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard micGranted else { throw MediaError.micDenied }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playAndRecord,
            mode: kind == .video ? .videoChat : .voiceChat,
            options: [.allowBluetooth]
        )
        if useCallKitAudio {
            // CallKit activates the session and tells WebRTC (see P2PCallCoordinator).
            let rtc = LKRTCAudioSession.sharedInstance()
            rtc.useManualAudio = true
            #if canImport(CallKit)
            if CallKitBridge.shared.isAudioSessionActive {
                rtc.audioSessionDidActivate(session)
                rtc.isAudioEnabled = true
            } else {
                rtc.isAudioEnabled = false
            }
            #endif
        } else {
            try? session.setActive(true)
        }
        applySpeaker()
        CallMediaControls.shared.setMicrophoneMuted = { [weak self] muted in
            guard let self, let track = self.audioTrack else { return }
            track.isEnabled = !muted
            self.micEnabled = track.isEnabled
        }

        let factory = P2PWebRTC.factory
        let audioSource = factory.audioSource(with: LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        let audio = factory.audioTrack(with: audioSource, trackId: "p2p-audio-\(callId)")
        audio.isEnabled = params.startWithMicOn
        audioTrack = audio
        micEnabled = audio.isEnabled

        if kind == .video, params.startWithCameraOn {
            do {
                try await startCamera()
            } catch {
                // A video call can still go ahead audio only.
                log("camera unavailable: \(error)")
                notice = "Could not access your camera"
                camEnabled = false
            }
        }
    }

    private func startCamera() async throws {
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: granted = true
        case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .video)
        default: granted = false
        }
        guard granted else { throw MediaError.cameraDenied }

        let factory = P2PWebRTC.factory
        let source = factory.videoSource()
        let capturer = LKRTCCameraVideoCapturer(delegate: source)
        let devices = LKRTCCameraVideoCapturer.captureDevices()
        guard let device = devices.first(where: { $0.position == cameraDevicePosition }) ?? devices.first else {
            throw MediaError.cameraDenied
        }
        let formats = LKRTCCameraVideoCapturer.supportedFormats(for: device)
        let target: Int32 = 1280
        guard let format = formats.min(by: { a, b in
            abs(CMVideoFormatDescriptionGetDimensions(a.formatDescription).width - target)
                < abs(CMVideoFormatDescriptionGetDimensions(b.formatDescription).width - target)
        }) else {
            throw MediaError.cameraDenied
        }
        let fps = Int(min(30, format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 30))

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            capturer.startCapture(with: device, format: format, fps: fps) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }

        let track = factory.videoTrack(with: source, trackId: "p2p-video-\(callId)")
        self.videoSource = source
        self.capturer = capturer
        self.localVideoTrack = track
        self.camEnabled = true
        self.frontCamera = device.position != .back
    }

    private func stopCamera() async {
        let current = capturer
        capturer = nil
        localVideoTrack = nil
        videoSource = nil
        camEnabled = false
        guard let current else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            current.stopCapture { continuation.resume() }
        }
    }

    /// True when the host enabled the CallKit bridge, which then owns the audio session.
    private var useCallKitAudio: Bool {
        #if canImport(CallKit)
        return CallKitBridge.shared.isEnabled
        #else
        return false
        #endif
    }

    private func releaseMedia() {
        CallMediaControls.shared.setMicrophoneMuted = nil
        if useCallKitAudio {
            let rtc = LKRTCAudioSession.sharedInstance()
            rtc.isAudioEnabled = false
            rtc.useManualAudio = false
        }
        capturer?.stopCapture(completionHandler: {})
        capturer = nil
        videoSource = nil
        localVideoTrack = nil
        audioTrack = nil
        videoSender = nil
        if !useCallKitAudio {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    public func toggleMic() {
        guard !disposed, let audioTrack else { return }
        audioTrack.isEnabled.toggle()
        micEnabled = audioTrack.isEnabled
    }

    /// Turning the camera off stops sending video and releases the device;
    /// turning it on opens the camera again and swaps it into the existing
    /// sender, so no renegotiation is needed.
    public func toggleCamera() async {
        guard !disposed, kind == .video, let videoSender, !cameraBusy else { return }
        cameraBusy = true
        defer { cameraBusy = false }
        if localVideoTrack != nil {
            videoSender.track = nil
            await stopCamera()
            notice = nil
        } else {
            do {
                try await startCamera()
                if disposed { return }
                videoSender.track = localVideoTrack
                notice = nil
            } catch {
                log("camera toggle failed: \(error)")
                notice = Self.describeMediaError(error)
            }
        }
    }

    /// Loudspeaker or receiver.
    public func toggleSpeaker() {
        speakerOn.toggle()
        applySpeaker()
    }

    private func applySpeaker() {
        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(speakerOn ? .speaker : .none)
    }

    /// Switches between the front and back camera. The sender keeps its track:
    /// only the capture device behind the video source changes.
    public func flipCamera() async {
        guard !disposed, kind == .video, localVideoTrack != nil, let source = videoSource, !cameraBusy else { return }
        cameraBusy = true
        defer { cameraBusy = false }
        let next: AVCaptureDevice.Position = cameraDevicePosition == .front ? .back : .front
        let devices = LKRTCCameraVideoCapturer.captureDevices()
        guard let device = devices.first(where: { $0.position == next }),
              let format = LKRTCCameraVideoCapturer.supportedFormats(for: device).min(by: { a, b in
                  abs(CMVideoFormatDescriptionGetDimensions(a.formatDescription).width - 1280)
                      < abs(CMVideoFormatDescriptionGetDimensions(b.formatDescription).width - 1280)
              }) else {
            notice = "Could not switch the camera"
            return
        }
        let fps = Int(min(30, format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 30))
        let old = capturer
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if let old { old.stopCapture { continuation.resume() } } else { continuation.resume() }
        }
        let capturer = LKRTCCameraVideoCapturer(delegate: source)
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                capturer.startCapture(with: device, format: format, fps: fps) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
            self.capturer = capturer
            cameraDevicePosition = next
            frontCamera = next == .front
        } catch {
            log("camera flip failed: \(error)")
            notice = "Could not switch the camera"
        }
    }

    public func dismissNotice() {
        notice = nil
    }

    // MARK: - Peer connection

    private func createConnection(servers: [IceServerConfig]) -> Bool {
        let config = LKRTCConfiguration()
        config.iceServers = Self.rtcServers(servers)
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        config.iceCandidatePoolSize = 2

        guard let pc = P2PWebRTC.factory.peerConnection(
            with: config,
            constraints: LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil),
            delegate: peerDelegate
        ) else {
            return false
        }
        self.pc = pc

        peerDelegate.onCandidate = { [weak self] candidate in
            Task { @MainActor in
                guard let self, !self.disposed else { return }
                if self.candidateGateOpen { self.emitCandidate(candidate) } else { self.heldOutgoingCandidates.append(candidate) }
            }
        }
        peerDelegate.onConnectionState = { [weak self] state in
            Task { @MainActor in self?.onConnectionState(state) }
        }
        peerDelegate.onRemoteVideo = { [weak self] track in
            Task { @MainActor in self?.attachRemoteVideo(track) }
        }

        let streamIds = ["p2p-\(callId)"]
        if let audioTrack { _ = pc.add(audioTrack, streamIds: streamIds) }
        if kind == .video {
            if let localVideoTrack {
                videoSender = pc.add(localVideoTrack, streamIds: streamIds)
            } else {
                // Camera starts off: keep a video section so it can be turned on
                // later without renegotiating.
                let transceiverInit = LKRTCRtpTransceiverInit()
                transceiverInit.direction = .sendRecv
                videoSender = pc.addTransceiver(of: .video, init: transceiverInit)?.sender
            }
        }
        return true
    }

    private func attachRemoteVideo(_ track: LKRTCVideoTrack) {
        guard !disposed else { return }
        watchedTrack?.remove(frameWatcher)
        track.add(frameWatcher)
        watchedTrack = track
        remoteVideoTrack = track
        liveTimer?.cancel()
        liveTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !self.disposed else { return }
                let live = self.frameWatcher.hasRecentFrame
                if live != self.remoteVideoLive { self.remoteVideoLive = live }
            }
        }
    }

    private static func rtcServers(_ servers: [IceServerConfig]) -> [LKRTCIceServer] {
        servers.map { LKRTCIceServer(urlStrings: $0.urls, username: $0.username, credential: $0.credential) }
    }

    private func emitCandidate(_ candidate: P2PCandidatePayload) {
        sentCandidates.append(candidate)
        sendSignal(.candidate, .candidate(candidate))
    }

    private func openCandidateGate() {
        candidateGateOpen = true
        let held = heldOutgoingCandidates
        heldOutgoingCandidates = []
        for candidate in held { emitCandidate(candidate) }
    }

    private func sendSignal(_ name: P2PSignalName, _ payload: P2PSignalPayload) {
        P2PRuntime.shared.send(
            peerXmppUsername: params.peerXmppUsername,
            callId: callId,
            signal: name,
            payload: payload
        )
    }

    // MARK: - Negotiation

    private func enqueue(_ job: @escaping () async throws -> Void) {
        let previous = queue
        queue = Task { [weak self] in
            await previous.value
            guard let self, !self.disposed else { return }
            do {
                try await job()
            } catch {
                self.log("negotiation step failed: \(error)")
                // A broken negotiation cannot recover on its own.
                self.fail("Could not set up the call", reason: "negotiation-error")
            }
        }
    }

    private func later(_ seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self, !self.disposed else { return }
            work()
        }
        timers.append(task)
        return task
    }

    private func createOffer(iceRestart: Bool) async throws -> LKRTCSessionDescription {
        guard let pc else { throw P2PError.noConnection }
        let constraints = LKRTCMediaConstraints(
            mandatoryConstraints: iceRestart ? ["IceRestart": "true"] : nil,
            optionalConstraints: nil
        )
        return try await withCheckedThrowingContinuation { continuation in
            pc.offer(for: constraints) { sdp, error in
                if let sdp { continuation.resume(returning: sdp) } else { continuation.resume(throwing: error ?? P2PError.noDescription) }
            }
        }
    }

    private func createAnswer() async throws -> LKRTCSessionDescription {
        guard let pc else { throw P2PError.noConnection }
        let constraints = LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        return try await withCheckedThrowingContinuation { continuation in
            pc.answer(for: constraints) { sdp, error in
                if let sdp { continuation.resume(returning: sdp) } else { continuation.resume(throwing: error ?? P2PError.noDescription) }
            }
        }
    }

    private func setLocal(_ sdp: LKRTCSessionDescription) async throws {
        guard let pc else { throw P2PError.noConnection }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pc.setLocalDescription(sdp) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    private func setRemote(_ sdp: LKRTCSessionDescription) async throws {
        guard let pc else { throw P2PError.noConnection }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pc.setRemoteDescription(sdp) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    private enum P2PError: Error {
        case noConnection
        case noDescription
    }

    private func sendOffer(iceRestart: Bool) async throws {
        guard pc != nil, !disposed else { return }
        candidateGateOpen = false
        let offer = try await createOffer(iceRestart: iceRestart)
        try await setLocal(offer)
        if disposed { return }
        let sdp = pc?.localDescription?.sdp ?? offer.sdp
        negotiator.markLocalOffer()
        lastOffer = sdp
        sentCandidates = []
        sendSignal(.offer, .sdp(type: "offer", sdp: sdp))
        openCandidateGate()
    }

    private func scheduleOfferResends() {
        for seconds in Self.offerResend {
            _ = later(seconds) { [weak self] in
                guard let self, self.negotiator.awaitingAnswer, let offer = self.lastOffer else { return }
                self.log("re-sending offer")
                self.sendSignal(.offer, .sdp(type: "offer", sdp: offer))
                for candidate in self.sentCandidates { self.sendSignal(.candidate, .candidate(candidate)) }
            }
        }
    }

    private func runCommands(_ commands: [NegotiatorCommand]) async throws {
        for command in commands {
            guard !disposed, let pc else { return }
            switch command {
            case let .applyOffer(sdp, initial, rollback):
                try await applyOffer(sdp: sdp, initial: initial, rollback: rollback)
            case let .applyAnswer(sdp):
                try await setRemote(LKRTCSessionDescription(type: .answer, sdp: sdp))
                try await runCommands(negotiator.markRemoteApplied())
                onNegotiated()
            case let .addCandidate(candidate):
                let ice = LKRTCIceCandidate(
                    sdp: candidate.candidate,
                    sdpMLineIndex: Int32(candidate.sdpMLineIndex ?? 0),
                    sdpMid: candidate.sdpMid
                )
                // A candidate from a superseded ICE session is harmless.
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    pc.add(ice) { _ in continuation.resume() }
                }
            case .remoteEnd:
                break // handled synchronously in receive()
            }
        }
    }

    private func applyOffer(sdp: String, initial: Bool, rollback: Bool) async throws {
        guard let pc else { return }
        if rollback, pc.signalingState == .haveLocalOffer {
            try await setLocal(LKRTCSessionDescription(type: .rollback, sdp: ""))
        }
        try await setRemote(LKRTCSessionDescription(type: .offer, sdp: sdp))
        try await runCommands(negotiator.markRemoteApplied())
        if disposed || self.pc == nil { return }

        candidateGateOpen = false
        let answer = try await createAnswer()
        try await setLocal(answer)
        if disposed { return }
        sendSignal(.answer, .sdp(type: "answer", sdp: self.pc?.localDescription?.sdp ?? answer.sdp))
        openCandidateGate()
        if initial { onNegotiated() }
    }

    private func onNegotiated() {
        if negotiated || disposed { return }
        negotiated = true
        if !connectedOnce {
            status = .connecting
            connectTimer = later(Self.connectTimeout) { [weak self] in
                guard let self, !self.connectedOnce else { return }
                self.fail("Could not connect the call", reason: "connect-timeout")
            }
        }
        events.onNegotiated()
    }

    // MARK: - Connection health

    private func onConnectionState(_ state: P2PConnState) {
        if disposed || state == lastConn { return }
        lastConn = state
        log("connection \(state.rawValue)")

        switch state {
        case .connected:
            graceTimer?.cancel()
            deadlineTimer?.cancel()
            connectTimer?.cancel()
            runIceAction(policy.onState(state))
            status = .connected
            if !connectedOnce {
                connectedOnce = true
                events.onConnected()
            }
        case .connecting:
            if connectedOnce { status = .reconnecting }
        case .disconnected, .failed:
            if connectedOnce { status = .reconnecting }
            runIceAction(policy.onState(state))
        default:
            break
        }
    }

    private func runIceAction(_ action: IceAction) {
        switch action {
        case let .wait(ms):
            graceTimer?.cancel()
            graceTimer = later(TimeInterval(ms) / 1000) { [weak self] in
                guard let self else { return }
                self.runIceAction(self.policy.onGraceElapsed())
            }
        case let .restart(deadlineMs):
            graceTimer?.cancel()
            deadlineTimer?.cancel()
            deadlineTimer = later(TimeInterval(deadlineMs) / 1000) { [weak self] in
                guard let self else { return }
                self.runIceAction(self.policy.onRestartDeadline(stillDown: self.lastConn != .connected))
            }
            enqueue { [weak self] in try await self?.restartIce() }
        case .giveUp:
            fail("Connection lost", reason: "connection-failed")
        case .recovered, .none:
            break
        }
    }

    /// ICE restart with fresh TURN credentials; the policy decides when.
    private func restartIce() async throws {
        guard let pc, !disposed else { return }
        if let fresh = await CallsAPI.fetchIceServers()?.iceServers, !fresh.isEmpty, !disposed {
            let configuration = pc.configuration
            configuration.iceServers = Self.rtcServers(fresh)
            _ = pc.setConfiguration(configuration)
        }
        // A negotiation is already in flight (e.g. the peer is restarting too);
        // the restart deadline still guards the outcome.
        guard pc.signalingState == .stable else { return }
        pc.restartIce()
        try await sendOffer(iceRestart: true)
    }
}
