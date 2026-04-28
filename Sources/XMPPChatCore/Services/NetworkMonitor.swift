//
//  NetworkMonitor.swift
//  XMPPChatCore
//
//  Tracks system network reachability via `NWPathMonitor` and surfaces
//  online/offline transitions through `NotificationCenter`. The XMPP client
//  uses this to:
//    1. Skip reconnect attempts while we know the device has no link
//       (avoids burning the 10-attempt offline cap during a long outage).
//    2. Wake itself up the moment the link is restored — without this, the
//       client sits in `pausedDueToOfflineCap = true` forever and never
//       re-tries until the user sends a fresh action or backgrounds the
//       app (`SessionRecoveryManager` only fires on
//       `didBecomeActive`/`willEnterForeground`).
//

import Foundation
import Network

public final class NetworkMonitor {
    public static let shared = NetworkMonitor()

    /// Posted on the main queue when the device transitions from offline
    /// → online. Subscribers (e.g. `XMPPClient`) reset their offline gates
    /// and trigger an immediate reconnect.
    public static let networkBecameAvailableNotification = Notification.Name("NetworkMonitorOnline")

    /// Posted on the main queue when the device goes offline. Currently
    /// informational — `isOnline` is the source of truth checked by
    /// `XMPPClient.scheduleReconnect`.
    public static let networkBecameUnavailableNotification = Notification.Name("NetworkMonitorOffline")

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.ethora.NetworkMonitor", qos: .utility)
    private let stateLock = NSLock()
    private var _isOnline: Bool = true

    /// Best-known link state. Defaults optimistic (`true`) so we don't gate
    /// the very first connect on `NWPathMonitor`'s first callback (which is
    /// async from `start(queue:)`).
    public var isOnline: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _isOnline
    }

    private init() {
        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let nowOnline = path.status == .satisfied
            self.stateLock.lock()
            let wasOnline = self._isOnline
            self._isOnline = nowOnline
            self.stateLock.unlock()
            guard nowOnline != wasOnline else { return }
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: nowOnline
                        ? NetworkMonitor.networkBecameAvailableNotification
                        : NetworkMonitor.networkBecameUnavailableNotification,
                    object: self
                )
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
