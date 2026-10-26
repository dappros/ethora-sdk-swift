//
//  ChatRoomViewModel+Members.swift
//  XMPPChatUI
//
//  Room management from the chat info sheet: add and remove members, report
//  the room, leave it. Mirrors ChatProfileModal / AddMembersModal on web.
//

import Foundation
import XMPPChatCore

extension ChatRoomViewModel {
    private var chatName: String {
        (room.jid.components(separatedBy: "/").first ?? room.jid)
            .components(separatedBy: "@").first ?? ""
    }

    /// Only a moderator manages members (web `activeRoom.role === 'moderator'`).
    var canManageMembers: Bool {
        room.role == "moderator"
    }

    /// Adds a user to the room by username, then invites them over XMPP so the room
    /// shows up for them at once. Updates the member list shown in the sheet.
    func addMember(username raw: String) async throws {
        let username = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty, !chatName.isEmpty else { return }

        let added = try await RoomsAPI.postAddRoomMember(chatName: chatName, members: [username])

        if let conference = ConfigStore.shared.config.xmppSettings?.conference, !conference.isEmpty {
            client.operations.inviteRoomRequest(to: username, roomJid: room.jid, chatDomain: conference)
        }

        var members = room.members ?? []
        for member in added where !members.contains(where: { $0.id == member.id }) {
            members.append(member)
        }
        applyMembers(members)
    }

    /// Removes one member from the room.
    func removeMember(_ member: RoomMember) async throws {
        let identifier = member.xmppUsername ?? member.id
        guard !identifier.isEmpty, !chatName.isEmpty else { return }

        _ = try await RoomsAPI.deleteRoomMember(chatName: chatName, members: [identifier])
        applyMembers((room.members ?? []).filter { $0.id != member.id })
    }

    /// Reports the whole room.
    func reportRoom(category: String, text: String?) async throws {
        guard !chatName.isEmpty else { return }
        _ = try await RoomsAPI.postReportRoom(
            chatName: chatName,
            category: category,
            text: (text ?? "").isEmpty ? nil : text
        )
    }

    /// Leaves the room (presence, REST self removal, local hide), like the list swipe.
    func leaveCurrentRoom() async {
        let bareJid = room.jid.components(separatedBy: "/").first ?? room.jid
        await client.leaveRoom(roomJID: bareJid)
        if !chatName.isEmpty, !currentUserId.isEmpty {
            _ = try? await RoomsAPI.deleteRoomMember(chatName: chatName, members: [currentUserId])
        }
        RoomStore.shared.hideRoom(jid: room.jid)
        MessageCache.shared.clearMessages(forRoomJID: room.jid)
    }

    private func applyMembers(_ members: [RoomMember]) {
        var update = PartialRoomUpdate()
        update.members = members
        update.usersCnt = members.count
        RoomStore.shared.updateRoom(jid: room.jid, updates: update)
        room.members = members
        room.usersCnt = members.count
    }
}
