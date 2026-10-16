//
//  PushSubscriptionService.swift
//  XMPPChatCore
//
//  Mirrors RN pushSubscriptionService: XMPP MUC-SUB room subscriptions, run
//  with a bounded parallel pool (RN concurrency 8). Backend token
//  registration lives in `PushNotificationManager`.
//

import Foundation

public actor PushSubscriptionService {
    public static let shared = PushSubscriptionService()

    /// Rooms subscribed in parallel per sweep (RN `concurrency = 8`).
    public static let concurrency = 8

    private let subscribedRoomsKey = "ethora_push_subscribed_rooms"
    private var subscribedRooms: Set<String> = []
    private var initialized = false

    private init() {}

    /// Kept for source compatibility. Forwards to `PushNotificationManager.registerPushToken`.
    public func subscribeToPush(fcmToken: String) async throws {
        let manager = await MainActor.run { PushNotificationManager.shared }
        _ = try await manager.registerPushToken(fcmToken)
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

    /// Subscribes `roomJIDs` in parallel batches of `concurrency`. Rooms that
    /// fail get one more pass after a short pause.
    public func subscribeToRooms(
        client: XMPPClient,
        roomJIDs: [String],
        userNick: String? = nil
    ) async {
        guard !roomJIDs.isEmpty else { return }

        let failed = await subscribeBatch(client: client, roomJIDs: roomJIDs, userNick: userNick)
        guard !failed.isEmpty else { return }

        try? await Task.sleep(nanoseconds: 1_000_000_000)
        _ = await subscribeBatch(client: client, roomJIDs: failed, userNick: userNick)
    }

    /// Returns the rooms that did not subscribe.
    private func subscribeBatch(
        client: XMPPClient,
        roomJIDs: [String],
        userNick: String?
    ) async -> [String] {
        var failed: [String] = []
        var start = 0
        while start < roomJIDs.count {
            let end = min(start + Self.concurrency, roomJIDs.count)
            let batch = Array(roomJIDs[start..<end])
            let results = await withTaskGroup(of: (String, Bool).self) { group -> [(String, Bool)] in
                for roomJID in batch {
                    group.addTask {
                        let ok = await self.subscribeToRoom(client: client, roomJID: roomJID, userNick: userNick)
                        return (roomJID, ok)
                    }
                }
                var collected: [(String, Bool)] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }
            failed += results.filter { !$0.1 }.map { $0.0 }
            start = end
        }
        return failed
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

