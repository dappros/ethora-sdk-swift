//
//  PlaygroundLogStore.swift
//  SDKPlayground
//

import Combine
import Foundation
import SwiftUI
import XMPPChatCore

/// Ring buffer of log lines + subscription to XMPP `NotificationCenter` events.
@MainActor
final class PlaygroundLogStore: ObservableObject {
    struct LogLine: Identifiable, Equatable {
        let id = UUID()
        let date: Date
        let level: Level
        let message: String

        enum Level: String {
            case info, success, warning, error
        }
    }

    @Published private(set) var lines: [LogLine] = []
    private let maxLines = 500
    private var cancellables = Set<AnyCancellable>()

    init() {
        observeSDKNotifications()
    }

    func clear() {
        lines.removeAll()
        append("Logs cleared.", level: .info)
    }

    func append(_ message: String, level: LogLine.Level = .info) {
        let line = LogLine(date: Date(), level: level, message: message)
        lines.append(line)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }

    private func observeSDKNotifications() {
        let center = NotificationCenter.default
        let names: [(NSNotification.Name, String)] = [
            (NSNotification.Name("XMPPConnectionStatusChanged"), "XMPP status"),
            (NSNotification.Name("XMPPClientDidConnect"), "XMPP connected"),
            (NSNotification.Name("XMPPMessageReceived"), "XMPP message in"),
            (NSNotification.Name("RoomMessagesUpdated"), "Room messages updated"),
            (NSNotification.Name("XMPPHistoryLoadFailed"), "History load failed"),
        ]

        for (notificationName, label) in names {
            let key = notificationName.rawValue
            center.publisher(for: notificationName)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] note in
                    self?.appendNotification(label: label, nameKey: key, note: note)
                }
                .store(in: &cancellables)
        }
    }

    private func appendNotification(label: String, nameKey: String, note: Notification) {
        var parts: [String] = ["[\(label)]"]
        if let info = note.userInfo, !info.isEmpty {
            let desc = info.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
            parts.append(desc)
        } else {
            parts.append(nameKey)
        }
        let level: LogLine.Level
        if nameKey.contains("Failed") || nameKey.contains("failed") {
            level = .error
        } else if nameKey.contains("DidConnect") || nameKey.contains("Connect") {
            level = .success
        } else {
            level = .info
        }
        append(parts.joined(separator: " "), level: level)
    }
}
