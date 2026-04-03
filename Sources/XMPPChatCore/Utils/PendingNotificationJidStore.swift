//
//  PendingNotificationJidStore.swift
//  XMPPChatCore
//
//  Persists room JID from push payloads (parity with RN AsyncStorage key
//  `ethora_pending_notification_jid` in index.js / usePendingNotification).
//

import Foundation

public enum RemoteNotificationPayload {
    /// Extracts room / chat JID from APNs / FCM `userInfo` (flat `data` keys).
    public static func roomJid(from userInfo: [AnyHashable: Any]) -> String? {
        func stringValue(_ any: Any?) -> String? {
            switch any {
            case let s as String where !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
                return s.trimmingCharacters(in: .whitespacesAndNewlines)
            case let n as NSNumber:
                return n.stringValue
            default:
                return nil
            }
        }

        if let j = stringValue(userInfo["jid"]) { return j }
        if let j = stringValue(userInfo["roomJid"]) { return j }
        if let j = stringValue(userInfo["room_jid"]) { return j }

        if let data = userInfo["data"] as? [String: Any] {
            if let j = stringValue(data["jid"]) { return j }
        }

        // Some FCM payloads nest under google.c.a.*
        for (key, value) in userInfo {
            guard let keyStr = key as? String else { continue }
            if keyStr.lowercased().hasSuffix("jid"), let j = stringValue(value), j.contains("@") {
                return j
            }
        }
        return nil
    }
}

public enum PendingNotificationJidStore {
    /// Same key as `ethora-chat-component-rn` (`PENDING_NOTIFICATION_JID_KEY`).
    public static let userDefaultsKey = "ethora_pending_notification_jid"

    public static func store(jid: String) {
        let trimmed = jid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UserDefaults.standard.set(trimmed, forKey: userDefaultsKey)
        print("[Push] Saved pending notification jid: \(trimmed)")
    }

    public static func peekPendingBareJid() -> String? {
        guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return raw.components(separatedBy: "/").first ?? raw
    }

    public static func clearPendingJid() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}
