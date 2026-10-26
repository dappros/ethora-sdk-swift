//
//  P2PSignalInbox.swift
//  XMPPChatCore
//
//  Routes incoming p2p signals to the call that owns them. Signals can arrive
//  before anyone listens (the caller's offer is on the wire while the callee is
//  still on the ring screen), so signals for a callId with no listener are held
//  briefly and replayed in order when a controller attaches. The hold is small
//  and bounded on purpose. Mirrors src/calls/p2p/signalInbox.ts.
//

import Foundation

public enum SignalDelivery: Equatable, Sendable {
    case delivered
    case buffered
    case dropped
}

public final class P2PSignalInbox {
    private let ttl: TimeInterval
    private let maxPendingCalls: Int
    private let maxPerCall: Int
    private let now: () -> Date

    private var pending: [(callId: String, firstAt: Date, signals: [P2PSignal])] = []
    private var handlers: [String: (P2PSignal) -> Void] = [:]
    private var closed: [String] = []
    private static let closedMemory = 16

    public init(
        ttl: TimeInterval = 20,
        maxPendingCalls: Int = 8,
        maxPerCall: Int = 96,
        now: @escaping () -> Date = Date.init
    ) {
        self.ttl = ttl
        self.maxPendingCalls = maxPendingCalls
        self.maxPerCall = maxPerCall
        self.now = now
    }

    private func sweep() {
        let cutoff = now().addingTimeInterval(-ttl)
        pending.removeAll { $0.firstAt < cutoff }
    }

    @discardableResult
    public func receive(_ signal: P2PSignal) -> SignalDelivery {
        if let handler = handlers[signal.callId] {
            handler(signal)
            return .delivered
        }
        if closed.contains(signal.callId) { return .dropped }

        sweep()
        if let index = pending.firstIndex(where: { $0.callId == signal.callId }) {
            if pending[index].signals.count >= maxPerCall { return .dropped }
            pending[index].signals.append(signal)
            return .buffered
        }
        if pending.count >= maxPendingCalls { pending.removeFirst() }
        pending.append((callId: signal.callId, firstAt: now(), signals: [signal]))
        return .buffered
    }

    /// Starts delivering a call's signals to `handler`, replaying anything held
    /// for it first (in arrival order). The returned closure detaches and
    /// marks the call closed.
    public func attach(callId: String, handler: @escaping (P2PSignal) -> Void) -> () -> Void {
        closed.removeAll { $0 == callId }
        sweep()
        var held: [P2PSignal] = []
        if let index = pending.firstIndex(where: { $0.callId == callId }) {
            held = pending[index].signals
            pending.remove(at: index)
        }
        handlers[callId] = handler
        for signal in held { handler(signal) }
        return { [weak self] in
            self?.handlers[callId] = nil
            self?.close(callId: callId)
        }
    }

    /// The call is over: forget held signals and drop future stragglers.
    public func close(callId: String) {
        pending.removeAll { $0.callId == callId }
        if !closed.contains(callId) {
            closed.append(callId)
            if closed.count > Self.closedMemory { closed.removeFirst() }
        }
    }

    public func clear() {
        pending.removeAll()
        handlers.removeAll()
        closed.removeAll()
    }
}
