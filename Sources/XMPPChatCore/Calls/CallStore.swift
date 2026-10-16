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
        peerXmppUsername: String?
    ) {
        let startedAt = Date()
        var next = State()
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
        peerXmppUsername: String?
    ) {
        cancelTimeout()
        var next = State()
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
    }

    /// Attaches the token to the outgoing call. Ignored unless an outgoing call
    /// for the same room is waiting (web setOutgoingCallToken).
    public func setOutgoingCallToken(roomJid: String, token: String, callId: String?) {
        guard state.direction == .outgoing else { return }
        if let current = state.roomJid, current != roomJid { return }
        cancelTimeout()
        state.phase = .connecting
        state.roomJid = roomJid
        state.token = token
        if let callId, !callId.isEmpty { state.callId = callId }
        state.error = nil
        state.startedAt = state.startedAt ?? Date()
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

        let isTerminal = CallSignaling.isTerminalState(rawState)
        // A server call-log with no explicit state means the session concluded.
        let isServerCallLog = rawState.isEmpty && isCallLog

        if (roomMatches || callIdMatches) && (isTerminal || isServerCallLog) {
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
        let isPrivateAllowed = videoCalls.allowedRoomTypes.contains("private")

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

        let roomJid = resolvedRoom?.jid ?? (token.room.contains("@") ? token.room : "")
        guard !roomJid.isEmpty else { return }

        // Prefer the caller's name over a sentinel room title such as "deleted".
        let resolvedTitle = (resolvedRoom?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let titleLooksBad = resolvedTitle.isEmpty
            || ["deleted", "deleted user", "unknown", "null"].contains(resolvedTitle.lowercased())
        let preferred = (!token.callerName.isEmpty && titleLooksBad) ? token.callerName : resolvedTitle
        let incomingRoomName: String
        if !preferred.isEmpty {
            incomingRoomName = preferred
        } else if !token.callerName.isEmpty {
            incomingRoomName = token.callerName
        } else {
            incomingRoomName = token.room
        }

        // A call-invite hint overrides the stanza kind (the server does not
        // carry it on the token). Consumed only after the gates above pass.
        let kind = consumeKindHint([token.room, token.callId]) ?? token.stanzaKind
        let callId = token.callId ?? token.jwtCallId
        let peer = CallSignaling.derivePeerXmppUsername(
            bareRoomName: token.room,
            selfXmppUsername: selfXmppUsername
        )

        let isOutgoingMatch = state.direction == .outgoing && (
            state.roomJid == roomJid
                || state.roomName == incomingRoomName
                || state.roomBareName == token.room
        )
        if isOutgoingMatch {
            setOutgoingCallToken(roomJid: roomJid, token: token.token, callId: callId)
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
            peerXmppUsername: peer
        )
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
