//
//  CallStore.swift
//  XMPPChatCore
//
//  Main-actor state machine for the current 1:1 call. Mirrors
//  src/roomStore/callSlice.ts and the incoming handler in
//  src/networking/callTokenStanza.ts. Network side effects (signals, REST,
//  call-log entries) live in CallService.
//

import Foundation
import Combine

@MainActor
public final class CallStore: ObservableObject {
    public static let shared = CallStore()

    /// Seconds an outgoing call may ring before it is given up
    /// (web OUTGOING_CALL_TIMEOUT_MS).
    public static let defaultOutgoingCallTimeout: TimeInterval = 30

    public struct State: Equatable {
        public var phase: CallPhase = .idle
        public var direction: CallDirection?
        public var kind: CallKind = .video
        public var roomJid: String?
        public var roomName: String?
        public var roomBareName: String?
        /// Stable id from the call-token (or JWT metadata). Echoed on signals so
        /// the peer can correlate them.
        public var callId: String?
        public var peerXmppUsername: String?
        public var token: String?
        /// Transport of this call. The server picks it; `.livekit` unless the
        /// call-token said `mode=p2p`.
        public var mode: CallMode = .livekit
        /// Group room call (always LiveKit): more than two participants, so the
        /// session must not end when one remote participant leaves.
        public var isGroup = false
        /// LiveKit URL sent on the call-token by the system account, if any.
        /// Wins over `config.videoCalls.livekitUrl`.
        public var livekitUrl: String?
        /// ICE servers sent on a p2p call-token (system account only).
        public var iceServers: [IceServerConfig]?
        /// Caller display name from the call-token, when known.
        public var callerName: String?
        public var callerXmppUsername: String?
        public var error: String?
        public var startedAt: Date?
        /// When the call connected. Used for the local call-log duration.
        public var connectedAt: Date?

        public init() {}
    }

    @Published public private(set) var state = State()

    private let outgoingCallTimeout: TimeInterval
    private var timeoutTask: Task<Void, Never>?
    private var kindHints: [String: (kind: CallKind, expiresAt: Date)] = [:]

    init(outgoingCallTimeout: TimeInterval = CallStore.defaultOutgoingCallTimeout) {
        self.outgoingCallTimeout = outgoingCallTimeout
    }

    /// True while a call is ringing, connecting or active.
    public var isBusy: Bool { state.phase != .idle }

    // MARK: - Transitions (web callSlice reducers)

    public func startOutgoingCall(
        roomJid: String,
        roomName: String?,
        roomBareName: String?,
        kind: CallKind,
        peerXmppUsername: String?,
        isGroup: Bool = false
    ) {
        let startedAt = Date()
        var next = State()
        next.isGroup = isGroup
        next.phase = .requesting
        next.direction = .outgoing
        next.kind = kind
        next.roomJid = roomJid
        next.roomName = roomName
        next.roomBareName = roomBareName ?? CallSignaling.localPart(of: roomJid)
        next.peerXmppUsername = peerXmppUsername
        next.startedAt = startedAt
        state = next
        scheduleOutgoingTimeout(startedAt: startedAt)
    }

    public func setIncomingCallToken(
        roomJid: String,
        roomName: String?,
        roomBareName: String?,
        token: String,
        kind: CallKind,
        callId: String?,
        peerXmppUsername: String?,
        mode: CallMode = .livekit,
        livekitUrl: String? = nil,
        iceServers: [IceServerConfig]? = nil,
        callerName: String? = nil,
        callerXmppUsername: String? = nil,
        isGroup: Bool = false
    ) {
        cancelTimeout()
        var next = State()
        next.isGroup = isGroup
        next.callerXmppUsername = callerXmppUsername
        next.mode = mode
        next.livekitUrl = livekitUrl
        next.iceServers = iceServers
        next.callerName = callerName
        next.phase = .ringingIncoming
        next.direction = .incoming
        next.kind = kind
        next.roomJid = roomJid
        next.roomName = roomName
        next.roomBareName = roomBareName ?? CallSignaling.localPart(of: roomJid)
        next.callId = callId
        next.peerXmppUsername = peerXmppUsername
        next.token = token
        next.startedAt = Date()
        state = next
        if mode == .p2p {
            // The ring screen is up: let the server (and so the caller) know.
            CallsAPI.fireAndForget { await CallsAPI.reportCallState(.ringing, callId: callId) }
        }
    }

    /// Attaches the token to the outgoing call. Ignored unless an outgoing call
    /// for the same room is waiting (web setOutgoingCallToken).
    public func setOutgoingCallToken(roomJid: String, token: String, callId: String?, livekitUrl: String? = nil) {
        guard state.direction == .outgoing else { return }
        if let current = state.roomJid, current != roomJid { return }
        cancelTimeout()
        state.phase = .connecting
        state.roomJid = roomJid
        state.token = token
        if let livekitUrl, !livekitUrl.isEmpty { state.livekitUrl = livekitUrl }
        if let callId, !callId.isEmpty { state.callId = callId }
        state.error = nil
        state.startedAt = state.startedAt ?? Date()
    }

    /// The create response told the caller how the call is carried. Applied only
    /// to the very call that asked (`startedAt` must match), so a late response
    /// for a call the user already cancelled cannot leak into the next one.
    public func setOutgoingCallRoute(
        startedAt: Date?,
        callId: String?,
        mode: CallMode,
        livekitUrl: String?,
        iceServers: [IceServerConfig]?,
        group: Bool? = nil
    ) {
        guard state.direction == .outgoing, state.startedAt == startedAt else { return }
        // The LiveKit call-token can overtake the HTTP response, so a livekit
        // route may still be applied once the phase moved on to `connecting`.
        // A p2p route only makes sense while still dialling.
        if state.phase != .requesting {
            guard state.phase == .connecting, mode == .livekit else { return }
        }
        state.mode = mode
        if let group { state.isGroup = group }
        if let callId, !callId.isEmpty { state.callId = callId }
        state.livekitUrl = livekitUrl
        state.iceServers = mode == .p2p ? (iceServers ?? []) : nil
    }

    /// The p2p offer/answer exchange completed on the caller side.
    public func markNegotiated() {
        guard state.phase == .requesting else { return }
        state.phase = .connecting
    }

    public func acceptIncomingCall() {
        guard state.direction == .incoming else { return }
        state.phase = .connecting
        state.error = nil
        state.startedAt = state.startedAt ?? Date()
    }

    /// Marks the call as connected. Anchors `connectedAt` once.
    public func markConnected() {
        guard state.phase != .idle else { return }
        state.phase = .inCall
        state.error = nil
        state.connectedAt = state.connectedAt ?? Date()
    }

    public func setCallError(_ message: String) {
        cancelTimeout()
        state.phase = .error
        state.error = message
        state.startedAt = state.startedAt ?? Date()
    }

    public func setCallKind(_ kind: CallKind) {
        guard state.phase != .idle else { return }
        state.kind = kind
    }

    /// Clears the call. Used for call end, decline and dismissing an error.
    public func resetCall() {
        cancelTimeout()
        state = State()
    }

    // MARK: - Incoming signalling (web onCallTokenMessage / handleCallStateData)

    /// Applies a parsed incoming call event. `selfXmppUsername` is the local
    /// user, used to derive the peer for a 1:1 room.
    public func apply(_ event: CallSignalEvent, selfXmppUsername: String) {
        switch event {
        case let .invite(room, callId, kind):
            applyInvite(room: room, callId: callId, kind: kind)
        case let .state(rawState, callId, room, callLog):
            applyCallState(rawState: rawState, callId: callId, room: room, isCallLog: callLog != nil)
        case let .token(token):
            applyToken(token, selfXmppUsername: selfXmppUsername)
        }
    }

    private func applyInvite(room: String?, callId: String?, kind: CallKind) {
        if let room, !room.isEmpty { stashKindHint(room, kind) }
        if let callId, !callId.isEmpty { stashKindHint(callId, kind) }

        guard state.phase != .idle, state.kind != kind else { return }
        let roomMatches = room.map { candidate in
            !candidate.isEmpty && (
                state.roomBareName == candidate
                    || state.roomJid == candidate
                    || CallSignaling.localPart(of: state.roomJid ?? "") == candidate
            )
        } ?? false
        let callIdMatches = (callId ?? "").isEmpty == false && state.callId == callId
        if roomMatches || callIdMatches {
            state.kind = kind
        }
    }

    private func applyCallState(rawState: String, callId: String?, room: String?, isCallLog: Bool) {
        guard state.phase != .idle else { return }

        // One member declining a group call must not end it for everybody.
        if state.isGroup, rawState == "declined" { return }

        let roomAttr = room ?? ""
        let roomMatches = !roomAttr.isEmpty && (
            state.roomJid == roomAttr
                || state.roomName == roomAttr
                || state.roomBareName == roomAttr
                || CallSignaling.localPart(of: state.roomJid ?? "") == roomAttr
        )
        let callIdMatches = (callId ?? "").isEmpty == false
            && (state.callId ?? "").isEmpty == false
            && state.callId == callId

        // A signal naming a DIFFERENT call than the one on screen (e.g. the
        // server log of the previous call in the same room arriving late) must
        // not tear down the current one just because the room matches.
        let callIdConflicts = (callId ?? "").isEmpty == false
            && (state.callId ?? "").isEmpty == false
            && state.callId != callId

        let isTerminal = CallSignaling.isTerminalState(rawState)
        // A server call-log with no explicit state means the session concluded.
        let isServerCallLog = rawState.isEmpty && isCallLog

        if (callIdMatches || (roomMatches && !callIdConflicts)) && (isTerminal || isServerCallLog) {
            resetCall()
        }
    }

    private func applyToken(_ token: IncomingCallToken, selfXmppUsername: String) {
        guard let videoCalls = ConfigStore.shared.config.videoCalls, videoCalls.enabled else {
            return
        }

        let resolvedRoom = resolveRoom(byStanzaRoom: token.room)
        let usersCnt = resolvedRoom?.usersCnt ?? 0
        let isOneToOneLike = usersCnt > 0 && usersCnt <= 2

        if token.group {
            // Group room call (always LiveKit). The host may opt out through
            // allowedRoomTypes; a room we know to be private contradicts `group`
            // and a public room never rings.
            guard videoCalls.allowsCalls(in: .group) else { return }
            if let type = resolvedRoom?.type, type != .group { return }
        } else {
            let isPrivateAllowed = videoCalls.allowsCalls(in: .private)
            // Room type gate. Only 1:1 rooms (private, or two members) can ring.
            if let type = resolvedRoom?.type, type.rawValue != "private", !isOneToOneLike {
                return
            }
            if resolvedRoom?.type?.rawValue == "private", !isPrivateAllowed {
                return
            }
            if resolvedRoom?.type == nil, !token.room.contains("@"), !isOneToOneLike {
                return
            }
        }

        let roomJid = resolvedRoom?.jid ?? (token.room.contains("@") ? token.room : "")
        guard !roomJid.isEmpty else { return }

        // What the call is called on screen. The caller's own name wins; a
        // sentinel room title ("deleted") or a raw chat name (two joined JIDs)
        // is never shown. An empty result makes the UI show a neutral label.
        let resolvedTitle = (resolvedRoom?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let titleLooksBad = resolvedTitle.isEmpty
            || ["deleted", "deleted user", "unknown", "null"].contains(resolvedTitle.lowercased())
            || CallModeParsing.looksLikeRawRoomName(resolvedTitle)
        // In a group the ring names the ROOM; the person calling is carried
        // separately ("<person> is calling in <room>").
        let jwtName = token.group ? "" : CallModeParsing.sanitizeCallName(token.callerName)
        let goodTitle = titleLooksBad ? "" : resolvedTitle
        let incomingRoomName: String
        if token.group {
            incomingRoomName = [goodTitle, CallModeParsing.sanitizeCallName(token.room)].first { !$0.isEmpty } ?? ""
        } else {
            incomingRoomName = [
                token.attrCallerName,
                jwtName,
                goodTitle,
                CallModeParsing.sanitizeCallName(token.room),
            ].first { !$0.isEmpty } ?? ""
        }
        let callerName = [token.attrCallerName, jwtName].first { !$0.isEmpty }

        // A call-invite hint overrides the stanza kind (the server does not
        // carry it on the token). Consumed only after the gates above pass.
        let kind = consumeKindHint([token.room, token.callId]) ?? token.stanzaKind
        let callId = token.callId ?? token.jwtCallId
        // A group has no single peer; a "<a>-<b>" name there is a coincidence.
        let peer = token.group ? nil : (CallSignaling.derivePeerXmppUsername(
            bareRoomName: token.room,
            selfXmppUsername: selfXmppUsername
        ) ?? token.callerXmppUsername)

        if token.mode == .p2p || state.mode == .p2p {
            // Peer to peer (or an active p2p call): one call at a time, decided
            // by callId. The legacy LiveKit-over-LiveKit path below is untouched.
            let decision = CallModeDecision.incomingWhileBusy(
                current: CallModeDecision.Snapshot(
                    // A failed call left on screen no longer blocks a new one.
                    phase: state.phase == .error ? .idle : state.phase,
                    direction: state.direction,
                    mode: state.mode,
                    callId: state.callId,
                    roomBareName: state.roomBareName
                ),
                incomingMode: token.mode,
                incomingCallId: callId,
                incomingRoomBareName: token.room
            )
            switch decision {
            case .duplicate, .glareKeep:
                return
            case .busy:
                if token.mode == .p2p {
                    CallService.shared.rejectBusyP2P(
                        callId: callId,
                        peerXmppUsername: peer,
                        roomBareName: token.room
                    )
                }
                return
            case .glareYield:
                // Both sides dialled at once and the other call has the smaller
                // id: drop ours, then ring for theirs.
                CallService.shared.abandonOutgoingForGlare()
            case .accept, .replace:
                break
            }
            if token.mode == .p2p {
                guard (callId ?? "").isEmpty == false else { return }
                setIncomingCallToken(
                    roomJid: roomJid,
                    roomName: incomingRoomName,
                    roomBareName: token.room,
                    token: "",
                    kind: kind,
                    callId: callId,
                    peerXmppUsername: peer,
                    mode: .p2p,
                    iceServers: token.iceServers,
                    callerName: callerName
                )
                return
            }
        }

        let isOutgoingMatch = state.direction == .outgoing && (
            state.roomJid == roomJid
                || state.roomName == incomingRoomName
                || state.roomBareName == token.room
        )
        if isOutgoingMatch {
            setOutgoingCallToken(
                roomJid: roomJid,
                token: token.token,
                callId: callId,
                livekitUrl: token.livekitUrl
            )
            return
        }

        // Do not replace a call that is already in progress (web would overwrite it).
        guard state.phase == .idle || state.phase == .error else { return }

        setIncomingCallToken(
            roomJid: roomJid,
            roomName: incomingRoomName,
            roomBareName: token.room,
            token: token.token,
            kind: kind,
            callId: callId,
            peerXmppUsername: peer,
            mode: token.mode,
            livekitUrl: token.livekitUrl,
            iceServers: token.iceServers,
            callerName: callerName,
            callerXmppUsername: token.callerXmppUsername,
            isGroup: token.group
        )
    }

    // MARK: - Incoming call push

    /// Rings for an incoming call delivered by push (APNs / FCM data payload),
    /// for the app being backgrounded or closed when the XMPP call-token went
    /// out. Hosts call this from their PushKit / CallKit or notification
    /// handler (`CallPush.isCallPush` / `CallPush.parse` tell a call push from a
    /// chat push). A p2p push carries no LiveKit token: the ring starts the same
    /// way and the offer arrives over XMPP once the app is connected.
    @discardableResult
    public func applyPush(_ push: CallPush, selfXmppUsername: String) -> Bool {
        guard let videoCalls = ConfigStore.shared.config.videoCalls, videoCalls.enabled else { return false }
        if push.isGroup, !videoCalls.allowsCalls(in: .group) { return false }
        if !push.isGroup, !videoCalls.allowsCalls(in: .private) { return false }
        guard let bare = push.roomBareName, !bare.isEmpty else { return false }
        if push.mode == .livekit, (push.token ?? "").isEmpty { return false }
        if push.mode == .p2p, (push.callId ?? "").isEmpty { return false }
        guard state.phase == .idle || state.phase == .error else { return false }

        let resolvedRoom = resolveRoom(byStanzaRoom: bare)
        let conference = ClientRegistry.shared.getGlobalXMPPClient()?.conference ?? ""
        let roomJid = resolvedRoom?.jid
            ?? (push.roomRef?.contains("@") == true ? push.roomRef! : (conference.isEmpty ? "" : "\(bare)@\(conference)"))
        guard !roomJid.isEmpty else { return false }

        let name = CallModeParsing.sanitizeCallName(push.callerName)
        let peer = push.isGroup ? nil : (push.callerXmppUsername
            ?? CallSignaling.derivePeerXmppUsername(bareRoomName: bare, selfXmppUsername: selfXmppUsername))
        setIncomingCallToken(
            roomJid: roomJid,
            roomName: push.isGroup
                ? (CallModeParsing.sanitizeCallName(resolvedRoom?.name).isEmpty
                    ? CallModeParsing.sanitizeCallName(bare)
                    : CallModeParsing.sanitizeCallName(resolvedRoom?.name))
                : (name.isEmpty ? CallModeParsing.sanitizeCallName(bare) : name),
            roomBareName: bare,
            token: push.token ?? "",
            kind: push.kind,
            callId: push.callId,
            peerXmppUsername: peer,
            mode: push.mode,
            callerName: name.isEmpty ? nil : name,
            callerXmppUsername: push.callerXmppUsername,
            isGroup: push.isGroup
        )
        return true
    }

    // MARK: - Lookups

    /// Matches a stanza `room` value to a loaded room: full JID first, then JID
    /// localpart, then display name.
    private func resolveRoom(byStanzaRoom roomAttr: String) -> Room? {
        let rooms = RoomStore.shared.rooms
        if let byJid = rooms[roomAttr] { return byJid }
        if let byLocalPart = rooms.values.first(where: { CallSignaling.localPart(of: $0.jid) == roomAttr }) {
            return byLocalPart
        }
        return rooms.values.first(where: { $0.name == roomAttr })
    }

    // MARK: - Kind hints (web kindHints map, 60 s TTL)

    private func stashKindHint(_ key: String, _ kind: CallKind) {
        let now = Date()
        kindHints = kindHints.filter { $0.value.expiresAt >= now }
        kindHints[key] = (kind: kind, expiresAt: now.addingTimeInterval(CallSignaling.kindHintTTL))
    }

    private func consumeKindHint(_ keys: [String?]) -> CallKind? {
        let now = Date()
        for case let key? in keys where !key.isEmpty {
            if let hit = kindHints[key], hit.expiresAt >= now {
                kindHints[key] = nil
                return hit.kind
            }
        }
        return nil
    }

    // MARK: - Outgoing timeout

    private func scheduleOutgoingTimeout(startedAt: Date) {
        cancelTimeout()
        let seconds = outgoingCallTimeout
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            guard self.state.phase == .requesting, self.state.startedAt == startedAt else { return }
            self.setCallError("No answer - call timed out")
        }
    }

    private func cancelTimeout() {
        timeoutTask?.cancel()
        timeoutTask = nil
    }
}
