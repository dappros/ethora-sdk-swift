//
//  ComposingTracker.swift
//  XMPPChatCore
//
//  Per-room typing registry. Tracks every typer, not only the last one, and
//  expires a typer whose "paused" never arrived. Web keeps a single composing
//  list per room and clears it on paused, so the expiry is an addition that
//  keeps a lost "paused" from pinning the indicator on screen.
//

import Foundation

public final class ComposingTracker {
    /// How long a typer stays listed without a fresh "composing" or a "paused".
    public static let expirySeconds: TimeInterval = 30

    /// Called on the main queue when a room's typer list changes.
    /// Arguments: room JID, display names of current typers, whether anyone is typing.
    public var onChange: ((_ roomJID: String, _ typers: [String], _ isComposing: Bool) -> Void)?

    private struct Typer {
        let nickname: String
        var fullName: String
        var expiresAt: Date
    }

    /// Insertion order is kept so "A and B are typing" reads in arrival order.
    private var rooms: [String: [Typer]] = [:]
    /// Last list handed to `onChange`, per room. Comparing against this (not
    /// against a pre-mutation snapshot) is what lets an expiry publish.
    private var published: [String: [String]] = [:]

    public init() {}

    /// Applies one chat-state event. `nickname` is the MUC nick (XMPP username).
    public func apply(roomJID: String, nickname: String, fullName: String, isComposing: Bool, now: Date = Date()) {
        guard !roomJID.isEmpty, !nickname.isEmpty else { return }
        var typers = rooms[roomJID] ?? []
        typers.removeAll { $0.nickname == nickname }
        if isComposing {
            typers.append(Typer(
                nickname: nickname,
                fullName: fullName.isEmpty ? "User" : fullName,
                expiresAt: now.addingTimeInterval(Self.expirySeconds)
            ))
            scheduleExpiry(roomJID: roomJID)
        }
        rooms[roomJID] = typers.isEmpty ? nil : typers
        publishIfChanged(roomJID: roomJID, now: now)
    }

    /// Display names of typers whose entry has not expired.
    public func names(roomJID: String, now: Date = Date()) -> [String] {
        (rooms[roomJID] ?? []).filter { $0.expiresAt > now }.map(\.fullName)
    }

    /// Drops expired entries for one room. Runs from the scheduled expiry and is idempotent.
    public func pruneExpired(roomJID: String, now: Date = Date()) {
        if var typers = rooms[roomJID] {
            typers.removeAll { $0.expiresAt <= now }
            rooms[roomJID] = typers.isEmpty ? nil : typers
        }
        publishIfChanged(roomJID: roomJID, now: now)
    }

    private func scheduleExpiry(roomJID: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.expirySeconds + 0.5) { [weak self] in
            self?.pruneExpired(roomJID: roomJID)
        }
    }

    private func publishIfChanged(roomJID: String, now: Date) {
        let current = names(roomJID: roomJID, now: now)
        guard current != (published[roomJID] ?? []) else { return }
        published[roomJID] = current.isEmpty ? nil : current
        onChange?(roomJID, current, !current.isEmpty)
    }
}
