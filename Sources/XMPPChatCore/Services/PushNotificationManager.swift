//
//  PushNotificationManager.swift
//  XMPPChatCore
//

import Foundation

@MainActor
public final class PushNotificationManager {
    public static let shared = PushNotificationManager()

    private var fcmToken: String?
    private weak var client: XMPPClient?
    private var lastBackendSubscriptionKey: String?

    private init() {}

    public func configure(fcmToken: String, client: XMPPClient) {
        self.fcmToken = fcmToken
        self.client = client
        print("[Push] configure called. online=\(client.checkOnline()) rooms=\(RoomStore.shared.rooms.count)")

        Task {
            await subscribeBackendIfNeeded()
            await refreshRoomPushSubscriptions()
        }
    }

    public func attachClient(_ client: XMPPClient) {
        self.client = client
        guard let fcmToken, !fcmToken.isEmpty else {
            print("[Push] attachClient: waiting for FCM token")
            return
        }
        configure(fcmToken: fcmToken, client: client)
    }

    public func updateFCMToken(_ token: String) {
        fcmToken = token
        print("[Push] updateFCMToken called.")
        guard let client else { return }
        configure(fcmToken: token, client: client)
    }

    public func refreshRoomPushSubscriptions() async {
        await subscribeBackendIfNeeded()
        guard isPushEnabled else {
            print("[Push] refreshRoomPushSubscriptions skipped: push disabled")
            return
        }
        guard let client, client.checkOnline() else {
            print("[Push] refreshRoomPushSubscriptions skipped: client offline")
            return
        }
        let roomJIDs = Array(RoomStore.shared.rooms.keys)
        guard !roomJIDs.isEmpty else {
            print("[Push] refreshRoomPushSubscriptions skipped: no rooms")
            return
        }
        print("[Push] subscribing to room count: \(roomJIDs.count)")
        await PushSubscriptionService.shared.subscribeToRooms(client: client, roomJIDs: roomJIDs)
    }

    public func reset() async {
        fcmToken = nil
        client = nil
        lastBackendSubscriptionKey = nil
        await PushSubscriptionService.shared.reset()
    }

    private var isPushEnabled: Bool {
        ConfigStore.shared.config.push?.enabled ?? true
    }

    private func subscribeBackendIfNeeded() async {
        guard isPushEnabled else {
            print("[Push] subscribeBackendIfNeeded skipped: push disabled")
            return
        }
        guard let fcmToken, !fcmToken.isEmpty else {
            print("[Push] subscribeBackendIfNeeded skipped: missing fcmToken")
            return
        }
        guard UserStore.shared.isAuthenticated else {
            print("[Push] subscribeBackendIfNeeded skipped: user not authenticated")
            return
        }

        let userIdentity = UserStore.shared.currentUser?.walletAddress
            ?? UserStore.shared.currentUser?.id
            ?? "unknown"
        let subscriptionKey = "\(fcmToken)_\(userIdentity)"
        if lastBackendSubscriptionKey == subscriptionKey {
            return
        }

        do {
            try await PushSubscriptionService.shared.subscribeToPush(fcmToken: fcmToken)
            lastBackendSubscriptionKey = subscriptionKey
            print("[Push] backend push subscription OK")
        } catch {
            print("[Push] Backend subscription failed: \(error.localizedDescription)")
        }
    }
}

