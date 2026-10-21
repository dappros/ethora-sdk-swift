//
//  CallKitBridge.swift
//  XMPPChatCore
//
//  Optional CallKit integration, off until the host opts in with `enable`.
//  Reports incoming calls (p2p and LiveKit, 1:1 and group) to the system call
//  UI under a stable UUID per callId, wires answer / decline / end / mute from
//  CallKit to CallStore, and reports remote ends back. A push for a call and the
//  XMPP call-token for the same call are the same CallKit call (deduped by
//  callId). The PushKit side lives in CallKitPushRegistry.
//
//  The host app needs the "Voice over IP" background mode (for PushKit) and, for
//  a ringtone / icon, the values passed in `CallKitConfiguration`.
//

#if canImport(CallKit)
import AVFoundation
import CallKit
import Combine
import CryptoKit
import Foundation

public struct CallKitConfiguration {
    /// Name shown on the system call screen and in the call history.
    public var localizedName: String
    /// File name of a ringtone in the app bundle (optional).
    public var ringtoneSound: String?
    /// PNG template image for the call screen button (optional, 40x40 pt).
    public var iconTemplateImageData: Data?
    public var supportsVideo: Bool
    public var includesCallsInRecents: Bool

    public init(
        localizedName: String,
        ringtoneSound: String? = nil,
        iconTemplateImageData: Data? = nil,
        supportsVideo: Bool = true,
        includesCallsInRecents: Bool = false
    ) {
        self.localizedName = localizedName
        self.ringtoneSound = ringtoneSound
        self.iconTemplateImageData = iconTemplateImageData
        self.supportsVideo = supportsVideo
        self.includesCallsInRecents = includesCallsInRecents
    }
}

/// Hooks the active call's media layer registers so CallKit can drive it.
@MainActor
public final class CallMediaControls {
    public static let shared = CallMediaControls()
    private init() {}

    /// Mutes / unmutes the microphone of the active call.
    public var setMicrophoneMuted: ((Bool) -> Void)?
    /// The system activated the audio session for the call (CallKit owns it).
    public var audioSessionDidActivate: ((AVAudioSession) -> Void)?
    /// The system deactivated the audio session.
    public var audioSessionDidDeactivate: ((AVAudioSession) -> Void)?
}

@MainActor
public final class CallKitBridge: NSObject, ObservableObject {
    public static let shared = CallKitBridge()

    /// True once the host called `enable`.
    @Published public private(set) var isEnabled = false
    /// callIds whose incoming ring is shown by the system UI. The in-app ring
    /// card is hidden for these.
    @Published public private(set) var ringingHandledCallIds: Set<String> = []
    /// The system holds the audio session for a call right now.
    public private(set) var isAudioSessionActive = false

    private var provider: CXProvider?
    private let callController = CXCallController()
    private var cancellable: AnyCancellable?

    private struct Tracked {
        var callId: String
        var outgoing: Bool
        var answered: Bool
        var connectedReported: Bool
    }

    private var tracked: [UUID: Tracked] = [:]
    /// Calls the user answered in CallKit before CallStore knew about them.
    private var pendingAnswers: Set<UUID> = []
    /// Calls whose end was started by us (CXEndCallAction in flight).
    private var localEnding: Set<UUID> = []

    private override init() {
        super.init()
    }

    // MARK: - Identity

    /// Stable UUID for a callId (name based, v5 style), so the push and the XMPP
    /// call-token for one call map to one CallKit call.
    public static func uuid(forCallId callId: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data("ethora-call:\(callId)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    // MARK: - Opt in

    /// Turns the bridge on. Call once at launch, before the first VoIP push can
    /// arrive.
    public func enable(_ configuration: CallKitConfiguration) {
        guard !isEnabled else { return }
        let providerConfiguration = CXProviderConfiguration()
        providerConfiguration.supportsVideo = configuration.supportsVideo
        providerConfiguration.maximumCallGroups = 1
        providerConfiguration.maximumCallsPerCallGroup = 1
        providerConfiguration.supportedHandleTypes = [.generic]
        providerConfiguration.includesCallsInRecents = configuration.includesCallsInRecents
        providerConfiguration.ringtoneSound = configuration.ringtoneSound
        if let data = configuration.iconTemplateImageData {
            providerConfiguration.iconTemplateImageData = data
        }
        let provider = CXProvider(configuration: providerConfiguration)
        provider.setDelegate(self, queue: nil)
        self.provider = provider
        isEnabled = true

        cancellable = CallStore.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.reconcile(state) }
        reconcile(CallStore.shared.state)
    }

    /// Turns the bridge off and ends anything it was tracking.
    public func disable() {
        cancellable = nil
        provider?.invalidate()
        provider = nil
        tracked.removeAll()
        pendingAnswers.removeAll()
        localEnding.removeAll()
        ringingHandledCallIds = []
        isEnabled = false
    }

    /// Whether the system UI rings for this call, so the in-app card stays hidden.
    public func handlesRinging(for callId: String?) -> Bool {
        guard isEnabled, let callId, !callId.isEmpty else { return false }
        return ringingHandledCallIds.contains(callId)
    }

    // MARK: - PushKit entry point

    /// Handles a VoIP push payload. MUST be called synchronously from the PushKit
    /// delegate: iOS requires every VoIP push to be reported to CallKit, or the
    /// app is terminated. A call payload is reported and handed to CallStore; a
    /// payload that is not a call is reported and ended at once to satisfy iOS.
    /// - Returns: true when the payload was a call.
    @discardableResult
    public func handleVoIPPush(_ payload: [AnyHashable: Any], completion: (() -> Void)? = nil) -> Bool {
        guard isEnabled, let provider else {
            completion?()
            return false
        }
        guard CallPush.isCallPush(payload) else {
            // iOS demands a report even for a push we cannot use.
            let uuid = UUID()
            let update = CXCallUpdate()
            update.remoteHandle = CXHandle(type: .generic, value: "unknown")
            provider.reportNewIncomingCall(with: uuid, update: update) { _ in
                provider.reportCall(with: uuid, endedAt: Date(), reason: .failed)
                completion?()
            }
            return false
        }

        let push = CallPush.parse(payload)
        let callId = push.callId ?? UUID().uuidString
        let name = CallModeParsing.sanitizeCallName(push.callerName)
        reportIncoming(
            callId: callId,
            displayName: name.isEmpty ? "Incoming call" : name,
            video: push.kind == .video,
            completion: completion
        )
        let selfName = UserStore.shared.currentUser?.xmppUsername ?? ""
        _ = CallStore.shared.applyPush(push, selfXmppUsername: selfName)
        return true
    }

    // MARK: - Reporting

    private func reportIncoming(callId: String, displayName: String, video: Bool, completion: (() -> Void)? = nil) {
        guard let provider else { completion?(); return }
        let uuid = Self.uuid(forCallId: callId)

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: displayName)
        update.localizedCallerName = displayName
        update.hasVideo = video
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false

        if tracked[uuid] != nil {
            // Same call already reported (push first, XMPP token second): only
            // refresh what the system shows.
            provider.reportCall(with: uuid, updated: update)
            completion?()
            return
        }
        tracked[uuid] = Tracked(callId: callId, outgoing: false, answered: false, connectedReported: false)
        ringingHandledCallIds.insert(callId)
        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            Task { @MainActor in
                if error != nil {
                    // The system refused (Do Not Disturb, blocked, too many calls):
                    // fall back to the in-app ring.
                    self?.tracked[uuid] = nil
                    self?.ringingHandledCallIds.remove(callId)
                }
                completion?()
            }
        }
    }

    /// Mirrors CallStore into CallKit.
    private func reconcile(_ state: CallStore.State) {
        guard isEnabled, let provider else { return }

        if let callId = state.callId, !callId.isEmpty, state.phase != .idle {
            let uuid = Self.uuid(forCallId: callId)
            switch (state.direction, state.phase) {
            case (.incoming?, .ringingIncoming):
                let name = (state.callerName ?? "").isEmpty ? (state.roomName ?? "") : (state.callerName ?? "")
                reportIncoming(
                    callId: callId,
                    displayName: name.isEmpty ? "Incoming call" : name,
                    video: state.kind == .video
                )
                // The user answered in the system UI before the call reached us.
                if pendingAnswers.remove(uuid) != nil {
                    CallService.shared.acceptIncomingCall()
                }
            case (.outgoing?, _):
                if tracked[uuid] == nil, state.phase != .error {
                    startOutgoing(callId: callId, uuid: uuid, state: state)
                }
            default:
                break
            }

            if state.phase == .inCall, var entry = tracked[uuid], !entry.connectedReported {
                entry.connectedReported = true
                entry.answered = true
                tracked[uuid] = entry
                if entry.outgoing { provider.reportOutgoingCall(with: uuid, connectedAt: Date()) }
            }
        }

        // A tracked call that is no longer the current call has ended.
        let currentUUID = state.phase != .idle && state.callId != nil
            ? Self.uuid(forCallId: state.callId ?? "")
            : nil
        for (uuid, entry) in tracked where uuid != currentUUID {
            // A call in error state still has its callId; only drop when it is gone.
            if localEnding.contains(uuid) { continue }
            let reason: CXCallEndedReason = entry.answered || entry.connectedReported ? .remoteEnded : .unanswered
            provider.reportCall(with: uuid, endedAt: Date(), reason: reason)
            forget(uuid)
        }
    }

    private func startOutgoing(callId: String, uuid: UUID, state: CallStore.State) {
        let name = (state.roomName ?? "").isEmpty ? "Call" : (state.roomName ?? "")
        tracked[uuid] = Tracked(callId: callId, outgoing: true, answered: true, connectedReported: false)
        let handle = CXHandle(type: .generic, value: name)
        let action = CXStartCallAction(call: uuid, handle: handle)
        action.isVideo = state.kind == .video
        action.contactIdentifier = name
        callController.request(CXTransaction(action: action)) { [weak self] error in
            if error != nil {
                Task { @MainActor in self?.forget(uuid) }
            }
        }
    }

    private func forget(_ uuid: UUID) {
        if let entry = tracked[uuid] { ringingHandledCallIds.remove(entry.callId) }
        tracked[uuid] = nil
        pendingAnswers.remove(uuid)
        localEnding.remove(uuid)
    }

    /// The user ended / declined the call from inside the app: tell CallKit so the
    /// system call UI goes away. Called by CallService.
    func localEnd(callId: String?) {
        guard isEnabled, let callId, !callId.isEmpty else { return }
        let uuid = Self.uuid(forCallId: callId)
        guard tracked[uuid] != nil, !localEnding.contains(uuid) else { return }
        localEnding.insert(uuid)
        callController.request(CXTransaction(action: CXEndCallAction(call: uuid))) { [weak self] error in
            if error != nil {
                Task { @MainActor in
                    self?.provider?.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
                    self?.forget(uuid)
                }
            }
        }
    }
}

// MARK: - CXProviderDelegate

extension CallKitBridge: CXProviderDelegate {
    nonisolated public func providerDidReset(_ provider: CXProvider) {
        Task { @MainActor in
            self.tracked.removeAll()
            self.pendingAnswers.removeAll()
            self.localEnding.removeAll()
            self.ringingHandledCallIds = []
            if CallStore.shared.isBusy { CallStore.shared.resetCall() }
        }
    }

    nonisolated public func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        Task { @MainActor in
            provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
            action.fulfill()
        }
    }

    nonisolated public func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        Task { @MainActor in
            let state = CallStore.shared.state
            let current = (state.callId ?? "").isEmpty ? nil : Self.uuid(forCallId: state.callId ?? "")
            self.tracked[action.callUUID]?.answered = true
            if current == action.callUUID, state.phase == .ringingIncoming {
                CallService.shared.acceptIncomingCall()
            } else {
                // The call-token has not reached us yet: answer when it does.
                self.pendingAnswers.insert(action.callUUID)
            }
            action.fulfill()
        }
    }

    nonisolated public func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        Task { @MainActor in
            let uuid = action.callUUID
            let state = CallStore.shared.state
            let current = (state.callId ?? "").isEmpty ? nil : Self.uuid(forCallId: state.callId ?? "")
            self.localEnding.insert(uuid)
            if current == uuid {
                switch state.phase {
                case .ringingIncoming: CallService.shared.declineIncomingCall()
                case .error: CallService.shared.dismissError()
                default: CallService.shared.hangUp()
                }
            }
            self.forget(uuid)
            action.fulfill()
        }
    }

    nonisolated public func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        Task { @MainActor in
            CallMediaControls.shared.setMicrophoneMuted?(action.isMuted)
            action.fulfill()
        }
    }

    nonisolated public func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        Task { @MainActor in
            self.isAudioSessionActive = true
            CallMediaControls.shared.audioSessionDidActivate?(audioSession)
        }
    }

    nonisolated public func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        Task { @MainActor in
            self.isAudioSessionActive = false
            CallMediaControls.shared.audioSessionDidDeactivate?(audioSession)
        }
    }
}
#endif
