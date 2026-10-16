//
//  CallService.swift
//  XMPPChatCore
//
//  Places, accepts, declines and ends 1:1 calls. Owns the side effects that
//  CallStore does not: call-invite and call-state stanzas, the REST create, and
//  the local call-log entry. Mirrors the send side of callTokenStanza.ts,
//  callActions (terminateCall) and ChatHeader.placeCall on web.
//

import Foundation

@MainActor
public final class CallService {
    public static let shared = CallService()

    private init() {}

    // MARK: - Eligibility

    /// Whether the call buttons for `room` should be shown and enabled. Needs
    /// calls enabled with a LiveKit URL, a private room, and no active call.
    public func canStartCall(room: Room?, config: VideoCallsConfig?) -> Bool {
        guard let room, let config, config.isCallingAvailable else { return false }
        return room.type?.rawValue == "private" && !CallStore.shared.isBusy
    }

    // MARK: - Outgoing

    /// Starts an outgoing call in a 1:1 room. Sends the invite, creates the call
    /// over REST, and records a failure on the call state.
    public func placeCall(room: Room, kind: CallKind) async {
        let videoCalls = ConfigStore.shared.config.videoCalls
        guard canStartCall(room: room, config: videoCalls) else { return }

        let chatName = CallSignaling.localPart(of: room.jid)
        guard !chatName.isEmpty else { return }

        let selfLocal = CallSignaling.localPart(of: currentXmppUsername)
        let peer = (room.members ?? []).first { member in
            let local = CallSignaling.localPart(of: member.xmppUsername ?? "")
            return !local.isEmpty && local != selfLocal
        }
        let peerXmppUsername = peer?.xmppUsername

        // Never show "deleted" or a raw id as the dial title. Prefer the peer's name.
        let rawTitle = room.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let isBadTitle = rawTitle.isEmpty
            || ["deleted", "deleted user", "unknown", "null"].contains(rawTitle.lowercased())
        let peerDisplay = peer.map { member -> String in
            let full = "\(member.firstName ?? "") \(member.lastName ?? "")"
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return full.isEmpty ? (member.name ?? "") : full
        } ?? ""
        let dialName = [isBadTitle ? peerDisplay : rawTitle, peerDisplay, chatName]
            .first { !$0.isEmpty } ?? chatName

        CallStore.shared.startOutgoingCall(
            roomJid: room.jid,
            roomName: dialName,
            roomBareName: chatName,
            kind: kind,
            peerXmppUsername: peerXmppUsername
        )

        // The server does not carry `kind` on the call-token, so tell the peer
        // directly first. The invite usually arrives before the relayed token.
        if let peerXmppUsername, !peerXmppUsername.isEmpty {
            ClientRegistry.shared.getGlobalXMPPClient()?.operations.sendCallInvite(
                kind: kind,
                peerXmppUsername: peerXmppUsername,
                roomBareName: chatName
            )
        }

        do {
            try await CallsAPI.createChatCall(chatName: chatName, kind: kind)
        } catch {
            CallStore.shared.setCallError(error.localizedDescription)
        }
    }

    /// Cancels a ringing outgoing call, or hangs up an active one.
    public func hangUp() {
        let snapshot = CallStore.shared.state
        let signal: CallSignalState = snapshot.phase == .requesting ? .cancelled : .ended
        endCall(signal: signal)
    }

    /// Accepts the ringing incoming call.
    public func acceptIncomingCall() {
        CallStore.shared.acceptIncomingCall()
    }

    /// Declines the ringing incoming call and tells the caller.
    public func declineIncomingCall() {
        let snapshot = CallStore.shared.state
        sendSignal(.declined, from: snapshot)
        CallStore.shared.resetCall()
    }

    /// Clears a failed call so the user can try again.
    public func dismissError() {
        CallStore.shared.resetCall()
    }

    /// The call reached the room and the local side is connected. Remote
    /// hang-ups arrive through the call-state handler, not here.
    public func handleRemoteParticipantsGone() {
        endCall(signal: .ended)
    }

    // MARK: - End

    /// Writes the local call-log entry, sends the peer a signal, and clears
    /// state. Order matches web terminateCall.
    private func endCall(signal: CallSignalState) {
        let snapshot = CallStore.shared.state

        let hasCallId = !(snapshot.callId ?? "").isEmpty
        if let roomJid = snapshot.roomJid, hasCallId || snapshot.connectedAt != nil {
            let durationMs: Int64 = snapshot.connectedAt.map {
                Int64(Date().timeIntervalSince($0) * 1000)
            } ?? 0
            let caller: String?
            if snapshot.direction == .incoming {
                caller = snapshot.peerXmppUsername
            } else {
                caller = CallSignaling.localPart(of: currentXmppUsername)
            }
            let meta = CallLogMeta(
                callId: snapshot.callId ?? "",
                durationMs: durationMs,
                kind: snapshot.kind,
                callerXmppUsername: caller
            )
            insertLocalCallLog(roomJid: roomJid, meta: meta)
        }

        sendSignal(signal, from: snapshot)
        CallStore.shared.resetCall()
    }

    private func sendSignal(_ signal: CallSignalState, from snapshot: CallStore.State) {
        guard let peer = snapshot.peerXmppUsername, !peer.isEmpty else { return }
        let roomBareName = snapshot.roomBareName
            ?? CallSignaling.localPart(of: snapshot.roomJid ?? "")
        ClientRegistry.shared.getGlobalXMPPClient()?.operations.sendCallState(
            state: signal,
            peerXmppUsername: peer,
            callId: snapshot.callId ?? "",
            roomBareName: roomBareName
        )
    }

    // MARK: - Call-log entry

    /// Adds a call-log row to the room. The server copy usually follows and is
    /// merged by callId in RoomStore.
    private func insertLocalCallLog(roomJid: String, meta: CallLogMeta) {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let id = meta.callId.isEmpty ? "calllog-\(nowMs)" : "calllog-\(meta.callId)"
        var message = Message(
            id: id,
            user: User(id: UserStore.shared.currentUser?.id ?? ""),
            date: Date(),
            body: CallLogFormatter.fallbackBody(for: meta),
            roomJid: roomJid,
            timestamp: nowMs
        )
        message.isSystemMessage = "true"
        message.callLog = meta

        RoomStore.shared.addMessage(message, toRoomJID: roomJid)
        NotificationCenter.default.post(
            name: NSNotification.Name("XMPPMessageReceived"),
            object: nil,
            userInfo: ["message": message, "roomJID": roomJid]
        )
    }

    private var currentXmppUsername: String {
        UserStore.shared.currentUser?.xmppUsername ?? ""
    }
}
