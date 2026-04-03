//
//  PushSubscriptionService.swift
//  XMPPChatCore
//
//  Mirrors RN pushSubscriptionService:
//  backend push subscribe + XMPP MUC-SUB room subscriptions.
//

import Foundation

public actor PushSubscriptionService {
    public static let shared = PushSubscriptionService()

    private let subscribedRoomsKey = "ethora_push_subscribed_rooms"
    private var subscribedRooms: Set<String> = []
    private var initialized = false

    private init() {}

    public func subscribeToPush(fcmToken: String) async throws {
        try await PushAPI.registerPushToken(
            registrationToken: fcmToken,
            deviceType: .ios
        )
    }

    public func subscribeToRoom(
        client: XMPPClient,
        roomJID: String,
        userNick: String? = nil
    ) async -> Bool {
        await ensureInitialized()
        let bareRoomJID = roomJID.components(separatedBy: "/").first ?? roomJID
        if subscribedRooms.contains(bareRoomJID) {
            return true
        }

        guard client.checkOnline() else {
            return false
        }

        let nick = (userNick?.isEmpty == false) ? userNick! : client.username.components(separatedBy: "@").first
        guard let stanzaId = client.operations.subscribeToRoomPush(roomJID: bareRoomJID, nick: nick) else {
            return false
        }

        let success = await waitForSubscriptionResponse(client: client, stanzaId: stanzaId, timeout: 5.0)
        if success {
            subscribedRooms.insert(bareRoomJID)
            saveSubscribedRooms()
        }
        return success
    }

    public func subscribeToRooms(
        client: XMPPClient,
        roomJIDs: [String],
        userNick: String? = nil
    ) async {
        guard !roomJIDs.isEmpty else { return }

        var failed: [String] = []
        for roomJID in roomJIDs {
            let ok = await subscribeToRoom(client: client, roomJID: roomJID, userNick: userNick)
            if !ok {
                failed.append(roomJID)
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }

        if failed.isEmpty {
            return
        }

        try? await Task.sleep(nanoseconds: 1_000_000_000)
        for roomJID in failed {
            _ = await subscribeToRoom(client: client, roomJID: roomJID, userNick: userNick)
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
    }

    public func reset() {
        subscribedRooms.removeAll()
        initialized = false
        UserDefaults.standard.removeObject(forKey: subscribedRoomsKey)
    }

    private func ensureInitialized() {
        guard !initialized else { return }
        if let rooms = UserDefaults.standard.array(forKey: subscribedRoomsKey) as? [String] {
            subscribedRooms = Set(rooms)
        } else {
            subscribedRooms = []
        }
        initialized = true
    }

    private func saveSubscribedRooms() {
        UserDefaults.standard.set(Array(subscribedRooms), forKey: subscribedRoomsKey)
    }

    private func waitForSubscriptionResponse(
        client: XMPPClient,
        stanzaId: String,
        timeout: TimeInterval
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            var settled = false
            var observer: NSObjectProtocol?

            let finish: (Bool) -> Void = { result in
                guard !settled else { return }
                settled = true
                if let observer {
                    NotificationCenter.default.removeObserver(observer)
                }
                continuation.resume(returning: result)
            }

            observer = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("XMPPStanzaReceived"),
                object: client,
                queue: nil
            ) { notification in
                guard let stanza = notification.userInfo?["stanza"] as? XMPPStanza else { return }
                guard stanza.name == "iq", stanza.attributes["id"] == stanzaId else { return }

                let type = stanza.attributes["type"] ?? ""
                if type == "result" {
                    finish(true)
                } else if type == "error" {
                    finish(false)
                }
            }

            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                finish(false)
            }
        }
    }
}

