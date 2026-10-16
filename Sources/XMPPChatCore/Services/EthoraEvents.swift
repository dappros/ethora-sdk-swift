//
//  EthoraEvents.swift
//  XMPPChatCore
//
//  Server push pointers `<ethora-event xmlns="urn:ethora:events:1" .../>` inside a
//  type="headline" message from the server's own admin account.
//  Translated from src/networking/ethoraEvents.ts (onEthoraEvent, isTrustedEventSender).
//
//    user-profile-updated  xmppUsername="<appId>_<userId>"  -> re-read that user
//    chat-meta-updated     chatName="<appId>_<roomId>"      -> re-read that room
//
//  The payload is a pointer only. The client re-reads the user or room through
//  REST, so nothing in the stanza is shown or stored as is. Treat every
//  attribute as untrusted until it passes the checks below.
//

import Foundation

// MARK: - Parsing and trust (pure)

public enum EthoraEvent: Equatable {
    case userProfileUpdated(xmppUsername: String)
    case chatMetaUpdated(chatName: String)
}

public enum EthoraEvents {
    public static let xmlns = "urn:ethora:events:1"
    public static let mucSubEventNS = "http://jabber.org/protocol/pubsub#event"
    public static let maxKeyLength = 128
    /// Debounce before a room or user is re-read (ms in web, seconds here).
    public static let debounce: TimeInterval = 0.5
    /// Back-off per room after failed re-reads: 5 s, 30 s, then 120 s.
    public static let roomBackoff: [TimeInterval] = [5, 30, 120]

    /// The stanza that carries an `<ethora-event>`: the stanza itself, or the
    /// message inside a MUC-sub pubsub wrapper. Nil unless it is a headline with the child.
    public static func carrier(in stanza: XMPPStanza) -> XMPPStanza? {
        var candidates = [stanza]
        if let event = stanza.getChild("event", xmlns: mucSubEventNS),
           let items = event.getChild("items"),
           let item = items.getChild("item"),
           let inner = item.getChild("message") {
            candidates.append(inner)
        }
        return candidates.first { candidate in
            candidate.attributes["type"] == "headline"
                && candidate.getChild("ethora-event", xmlns: xmlns) != nil
        }
    }

    /// Domain part of a full or bare jid ("user@host/res" -> "host").
    public static func domain(ofJID jid: String) -> String {
        let bare = jid.components(separatedBy: "/").first ?? jid
        let parts = bare.components(separatedBy: "@")
        return parts.count == 2 ? parts[1].lowercased() : ""
    }

    /// True when a headline came from the server and not from a user or a room.
    /// - `from` must be a bare jid (no resource). The server stamps resources on
    ///   user and occupant stanzas, so a bare jid cannot be spoofed by a peer.
    /// - Its domain must be this session's own XMPP domain.
    /// - When `pinned` is non-empty, the sender must be listed (full jid or localpart).
    public static func isTrustedSender(from: String, ownDomain: String, pinned: [String]?) -> Bool {
        let trimmed = from.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains("/") else { return false }
        let parts = trimmed.components(separatedBy: "@")
        guard parts.count == 2 else { return false }
        let local = parts[0].lowercased()
        let domain = parts[1].lowercased()
        guard !local.isEmpty, !domain.isEmpty else { return false }
        let own = ownDomain.trimmingCharacters(in: .whitespaces).lowercased()
        guard !own.isEmpty, domain == own else { return false }

        guard let pinned, !pinned.isEmpty else { return true }
        return pinned.contains { entry in
            let value = entry.trimmingCharacters(in: .whitespaces).lowercased()
            return value == "\(local)@\(domain)" || value == local
        }
    }

    /// `<appId>_<id>` shape for an attribute that becomes a URL segment or a
    /// store key: charset, length cap, non-empty segments, and the session appId
    /// as prefix when the session has one.
    public static func isSafeEventKey(_ value: String?, sessionAppId: String?) -> Bool {
        guard let value, !value.isEmpty, value.count <= maxKeyLength else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        let segments = value.split(separator: "_", omittingEmptySubsequences: false)
        guard segments.count >= 2, segments.allSatisfy({ !$0.isEmpty }) else { return false }
        if let appId = sessionAppId?.trimmingCharacters(in: .whitespaces), !appId.isEmpty {
            guard value.hasPrefix("\(appId)_") else { return false }
        }
        return true
    }

    /// Parses the event carried by `carrier`. Nil for an unknown type, an
    /// `appId` that differs from the session, or an unsafe key.
    public static func parse(carrier: XMPPStanza, sessionAppId: String?) -> EthoraEvent? {
        guard let event = carrier.getChild("ethora-event", xmlns: xmlns) else { return nil }
        let appId = sessionAppId?.trimmingCharacters(in: .whitespaces)
        if let attrAppId = event.attributes["appId"],
           let appId, !appId.isEmpty, attrAppId != appId {
            return nil
        }
        switch event.attributes["type"] ?? "" {
        case "user-profile-updated":
            let id = event.attributes["xmppUsername"]
            guard isSafeEventKey(id, sessionAppId: appId), let id else { return nil }
            return .userProfileUpdated(xmppUsername: id)
        case "chat-meta-updated":
            let chatName = event.attributes["chatName"]
            guard isSafeEventKey(chatName, sessionAppId: appId), let chatName else { return nil }
            return .chatMetaUpdated(chatName: chatName)
        default:
            return nil
        }
    }

    /// Seconds to wait after the `count`-th failed re-read of a room.
    public static func backoff(forFailureCount count: Int) -> TimeInterval {
        let index = min(max(count, 1) - 1, roomBackoff.count - 1)
        return roomBackoff[index]
    }

    /// Titles the server sends for a deleted or unknown peer. Refused for private chats.
    public static func isBadTitle(_ title: String) -> Bool {
        let value = title.trimmingCharacters(in: .whitespaces).lowercased()
        return value.isEmpty || ["deleted", "deleted user", "unknown", "null"].contains(value)
    }

    /// Store patch for a chat-meta re-read. Members and messages are never touched:
    /// the response carries the whole member list and the loaded one may differ.
    /// `usersCnt` never goes down.
    public static func metaPatch(apiRoom: ApiRoom, current: Room) -> PartialRoomUpdate {
        var patch = PartialRoomUpdate()
        if let title = apiRoom.title {
            let trimmed = title.trimmingCharacters(in: .whitespaces)
            let refused = current.type == .private && isBadTitle(trimmed)
            if !refused {
                patch.title = trimmed
                patch.name = trimmed
            }
        }
        if let description = apiRoom.description {
            patch.description = description
        }
        if let picture = apiRoom.picture {
            patch.picture = picture
            if picture != "none" { patch.icon = picture }
        }
        let currentCount = RoomMembership.userCount(of: current)
        let fetchedCount = apiRoom.members?.count ?? currentCount
        patch.usersCnt = max(fetchedCount, currentCount)
        patch.type = apiRoom.type
        return patch
    }

    /// Members with the display names of `user` applied to the entry for
    /// `xmppUsername`. Nil when nothing would change.
    public static func patchedMembers(
        _ members: [RoomMember],
        xmppUsername: String,
        user: RoomMember
    ) -> [RoomMember]? {
        var changed = false
        let next = members.map { member -> RoomMember in
            guard member.xmppUsername == xmppUsername else { return member }
            guard member.firstName != user.firstName || member.lastName != user.lastName else {
                return member
            }
            changed = true
            return RoomMember(
                firstName: user.firstName,
                lastName: user.lastName,
                xmppUsername: member.xmppUsername,
                id: member.id,
                banStatus: member.banStatus,
                jid: member.jid,
                name: member.name,
                role: member.role,
                lastActive: member.lastActive,
                description: member.description
            )
        }
        return changed ? next : nil
    }
}

// MARK: - Handler (main actor)

/// Acts on trusted `<ethora-event>` pointers. Debounces per room and per user,
/// backs off failed room re-reads, and writes results to `RoomStore`.
@MainActor
public final class EthoraEventHandler {
    public static let shared = EthoraEventHandler()

    private struct RoomFailure {
        var count: Int
        var until: Date
    }

    private var roomTimers: [String: Task<Void, Never>] = [:]
    private var roomInflight: Set<String> = []
    private var roomAgain: Set<String> = []
    private var roomFailures: [String: RoomFailure] = [:]
    private var userTimers: [String: Task<Void, Never>] = [:]

    private init() {}

    /// Entry point from the stanza router. `ownDomain` is the domain of our own
    /// connected jid; when empty, the configured XMPP host is used.
    public func handle(carrier: XMPPStanza, ownDomain: String) {
        let config = ConfigStore.shared.config
        let sessionAppId = config.appId
        let domain = ownDomain.isEmpty ? (config.xmppSettings?.host ?? "") : ownDomain
        let from = carrier.attributes["from"] ?? ""

        guard EthoraEvents.isTrustedSender(from: from, ownDomain: domain, pinned: config.trustedEventSenders) else {
            print("[EthoraEvent] ignored: untrusted sender \(from)")
            return
        }
        guard let event = EthoraEvents.parse(carrier: carrier, sessionAppId: sessionAppId) else {
            return
        }
        switch event {
        case let .userProfileUpdated(xmppUsername):
            scheduleUserRefresh(xmppUsername, sessionAppId: sessionAppId)
        case let .chatMetaUpdated(chatName):
            // A room we do not hold is the invite flow's job, not ours.
            if findRoomJID(chatName) != nil {
                scheduleRoomRefresh(chatName, sessionAppId: sessionAppId)
            }
        }
    }

    /// Drops timers and per-room state (logout, tests).
    public func reset() {
        roomTimers.values.forEach { $0.cancel() }
        userTimers.values.forEach { $0.cancel() }
        roomTimers.removeAll()
        userTimers.removeAll()
        roomInflight.removeAll()
        roomAgain.removeAll()
        roomFailures.removeAll()
    }

    // MARK: Rooms

    private func findRoomJID(_ chatName: String) -> String? {
        RoomStore.shared.rooms.keys.first { jid in
            (jid.components(separatedBy: "@").first ?? jid) == chatName
        }
    }

    private func scheduleRoomRefresh(_ chatName: String, sessionAppId: String?) {
        roomTimers[chatName]?.cancel()
        roomTimers[chatName] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(EthoraEvents.debounce * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.roomTimers[chatName] = nil
            await self.runRoomRefresh(chatName, sessionAppId: sessionAppId)
        }
    }

    private func runRoomRefresh(_ chatName: String, sessionAppId: String?) async {
        if roomInflight.contains(chatName) {
            roomAgain.insert(chatName)
            return
        }
        if let failure = roomFailures[chatName], failure.until > Date() { return }
        guard let jid = findRoomJID(chatName),
              let token = UserStore.shared.token, !token.isEmpty else { return }

        roomInflight.insert(chatName)
        defer {
            roomInflight.remove(chatName)
            if roomAgain.remove(chatName) != nil {
                scheduleRoomRefresh(chatName, sessionAppId: sessionAppId)
            }
        }

        do {
            let apiRoom = try await RoomsAPI.getRoomByName(chatName: chatName, appId: sessionAppId)
            roomFailures[chatName] = nil
            guard let current = RoomStore.shared.rooms[jid] else { return }
            RoomStore.shared.updateRoom(jid: jid, updates: EthoraEvents.metaPatch(apiRoom: apiRoom, current: current))
        } catch {
            let count = (roomFailures[chatName]?.count ?? 0) + 1
            roomFailures[chatName] = RoomFailure(
                count: count,
                until: Date().addingTimeInterval(EthoraEvents.backoff(forFailureCount: count))
            )
            print("[EthoraEvent] room refresh failed for \(chatName): \(error.localizedDescription)")
        }
    }

    // MARK: Users

    private func scheduleUserRefresh(_ xmppUsername: String, sessionAppId: String?) {
        userTimers[xmppUsername]?.cancel()
        userTimers[xmppUsername] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(EthoraEvents.debounce * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.userTimers[xmppUsername] = nil
            await self.refreshUser(xmppUsername)
        }
    }

    /// Re-reads one profile and applies its display names to the user set and to
    /// every loaded member list that holds the user.
    private func refreshUser(_ xmppUsername: String) async {
        let outcome = await RoomMembersAPI.lookupUser(xmppUsername: xmppUsername)
        guard case let .ok(user) = outcome else { return }

        RoomStore.shared.usersSet[xmppUsername] = user
        for (jid, room) in RoomStore.shared.rooms {
            guard let members = room.members,
                  let next = EthoraEvents.patchedMembers(members, xmppUsername: xmppUsername, user: user) else {
                continue
            }
            RoomStore.shared.updateRoom(jid: jid, updates: {
                var patch = PartialRoomUpdate()
                patch.members = next
                return patch
            }())
        }
    }
}
