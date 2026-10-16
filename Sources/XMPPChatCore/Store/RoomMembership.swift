//
//  RoomMembership.swift
//  XMPPChatCore
//
//  Live membership bookkeeping for a room: members[] and usersCnt.
//  Mirrors adjustUsersCnt / isRoomMembersTruncated (helpers/roomUserCount.ts)
//  and the membership branches of stanzaHandlers.ts (onRoomMembershipChange
//  for the <message> path, onPresenceInRoom for the occupant <presence> path).
//

import Foundation

public enum RoomMembership {

    /// What a membership stanza does to a room. `none` means "nothing to write".
    public enum Update: Equatable {
        case none
        /// members[] and usersCnt both change.
        case set(members: [RoomMember], usersCnt: Int)
        /// Only usersCnt changes (a big room whose member page does not hold the user).
        case countOnly(usersCnt: Int)
    }

    /// Which stanza produced the change. The two paths differ on purpose,
    /// as in web: a presence join is never counted for a truncated room, a
    /// message-level add always is.
    public enum Source: Equatable {
        case message
        case presence
    }

    // MARK: - Counting

    /// The user count to display: the API total never loses to the members page.
    public static func userCount(of room: Room) -> Int {
        max(room.usersCnt, room.members?.count ?? 0)
    }

    /// True when the room is known to have more users than members loaded
    /// (big public rooms only carry a page of members).
    public static func isTruncated(_ room: Room) -> Bool {
        room.usersCnt > (room.members?.count ?? 0)
    }

    /// Next usersCnt after a live join (+1) or leave (-1). Adjusts the current
    /// count rather than recomputing from a possibly truncated members array.
    public static func adjustedUsersCnt(of room: Room, delta: Int, nextMembersCount: Int) -> Int {
        max(nextMembersCount, userCount(of: room) + delta, 0)
    }

    // MARK: - Affiliations

    /// Affiliations that mean "a member of the room" on a join.
    static let persistentAffiliations: Set<String> = ["owner", "admin", "member"]
    /// Affiliations that mean "removed from the room" (kick or leave of a member).
    static let removedAffiliations: Set<String> = ["none", "outcast"]

    // MARK: - Updates

    /// Membership change from `<message><x xmlns="muc#user"><item jid=... affiliation=.../></x></message>`.
    /// - Parameters:
    ///   - xmppUsername: local part of the item's jid.
    ///   - memberJid: full jid from the item, stored on a new member entry.
    ///   - affiliation: the item's affiliation attribute.
    public static func messageUpdate(
        room: Room,
        xmppUsername: String,
        memberJid: String,
        affiliation: String
    ) -> Update {
        let members = room.members ?? []
        let idx = members.firstIndex { $0.xmppUsername == xmppUsername }

        if removedAffiliations.contains(affiliation) {
            guard let idx else {
                // A truncated member page may not hold the leaver at all.
                guard isTruncated(room) else { return .none }
                return .countOnly(usersCnt: adjustedUsersCnt(of: room, delta: -1, nextMembersCount: members.count))
            }
            var next = members
            next.remove(at: idx)
            return .set(members: next, usersCnt: adjustedUsersCnt(of: room, delta: -1, nextMembersCount: next.count))
        }

        // Any other affiliation is a join. Already listed: nothing to add.
        guard idx == nil else { return .none }
        var next = members
        next.append(placeholderMember(xmppUsername: xmppUsername, jid: memberJid))
        return .set(members: next, usersCnt: adjustedUsersCnt(of: room, delta: 1, nextMembersCount: next.count))
    }

    /// Membership change from an occupant's `<presence>` (not our own).
    /// - Parameters:
    ///   - nickname: the occupant nick (the resource of `from`), which is the xmpp username.
    ///   - isUnavailable: `type="unavailable"` on the presence.
    public static func presenceUpdate(
        room: Room,
        nickname: String,
        affiliation: String,
        isUnavailable: Bool
    ) -> Update {
        let isKickedOut = isUnavailable && removedAffiliations.contains(affiliation)
        let isPersistentMember = !isUnavailable && persistentAffiliations.contains(affiliation)
        guard isKickedOut || isPersistentMember else { return .none }

        let members = room.members ?? []
        let idx = members.firstIndex { $0.xmppUsername == nickname }
        let truncated = isTruncated(room)

        if isKickedOut {
            guard let idx else {
                guard truncated else { return .none }
                return .countOnly(usersCnt: adjustedUsersCnt(of: room, delta: -1, nextMembersCount: members.count))
            }
            var next = members
            next.remove(at: idx)
            return .set(members: next, usersCnt: adjustedUsersCnt(of: room, delta: -1, nextMembersCount: next.count))
        }

        // A join seen only by presence is not counted for a truncated room:
        // we cannot tell it from a member that is simply off the loaded page.
        guard idx == nil, !truncated else { return .none }
        var next = members
        next.append(placeholderMember(xmppUsername: nickname, jid: ""))
        return .set(members: next, usersCnt: adjustedUsersCnt(of: room, delta: 1, nextMembersCount: next.count))
    }

    /// Store patch for an update, or nil when there is nothing to write.
    public static func partialUpdate(for update: Update) -> PartialRoomUpdate? {
        switch update {
        case .none:
            return nil
        case let .set(members, usersCnt):
            var patch = PartialRoomUpdate()
            patch.members = members
            patch.usersCnt = usersCnt
            return patch
        case let .countOnly(usersCnt):
            var patch = PartialRoomUpdate()
            patch.usersCnt = usersCnt
            return patch
        }
    }

    // MARK: - Helpers

    /// Member entry for a user we only know from the stanza. Names are filled
    /// in later by the user lookup (see `EthoraEventHandler`).
    static func placeholderMember(xmppUsername: String, jid: String) -> RoomMember {
        RoomMember(
            firstName: "",
            lastName: "",
            xmppUsername: xmppUsername,
            id: "",
            jid: jid
        )
    }
}

// MARK: - Store application

/// Applies a membership update to the shared `RoomStore`. Main actor only.
@MainActor
public enum RoomMembershipApplier {
    /// Writes `update` for the room at `roomJID`. No-op for unknown rooms or `.none`.
    public static func apply(_ update: RoomMembership.Update, roomJID: String) {
        guard let patch = RoomMembership.partialUpdate(for: update),
              RoomStore.shared.rooms[roomJID] != nil else { return }
        RoomStore.shared.updateRoom(jid: roomJID, updates: patch)
    }
}
