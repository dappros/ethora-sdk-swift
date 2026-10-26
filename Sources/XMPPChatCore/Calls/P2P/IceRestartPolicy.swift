//
//  IceRestartPolicy.swift
//  XMPPChatCore
//
//  ICE restart policy for a p2p call, kept apart from the peer connection so
//  it can be tested on its own. Mirrors src/calls/p2p/icePolicy.ts.
//
//   - `disconnected` is often transient, so wait a grace period first;
//   - `failed` is terminal for that ICE session, restart straight away;
//   - one restart per outage and a small cap per call;
//   - a restart that does not bring the connection back in time gives up.
//

import Foundation

public enum P2PConnState: String, Equatable, Sendable {
    case new
    case connecting
    case connected
    case disconnected
    case failed
    case closed
}

public enum IceAction: Equatable, Sendable {
    case none
    /// Re-check with `onGraceElapsed()` after `ms`.
    case wait(ms: Int)
    /// Restart; call `onRestartDeadline()` after `deadlineMs`.
    case restart(deadlineMs: Int)
    case recovered
    case giveUp(reason: String)
}

public struct IceRestartPolicy {
    private let graceMs: Int
    private let restartDeadlineMs: Int
    private let maxRestarts: Int
    private var restarts = 0
    private var attemptedThisOutage = false
    private var inOutage = false

    public init(graceMs: Int = 3_000, restartDeadlineMs: Int = 15_000, maxRestartsPerCall: Int = 3) {
        self.graceMs = graceMs
        self.restartDeadlineMs = restartDeadlineMs
        self.maxRestarts = maxRestartsPerCall
    }

    public var restartCount: Int { restarts }

    private mutating func tryRestart() -> IceAction {
        if attemptedThisOutage { return .giveUp(reason: "restart-did-not-recover") }
        if restarts >= maxRestarts { return .giveUp(reason: "too-many-restarts") }
        attemptedThisOutage = true
        restarts += 1
        return .restart(deadlineMs: restartDeadlineMs)
    }

    public mutating func onState(_ state: P2PConnState) -> IceAction {
        switch state {
        case .connected:
            let wasOutage = inOutage
            inOutage = false
            attemptedThisOutage = false
            return wasOutage ? .recovered : .none
        case .disconnected:
            inOutage = true
            if attemptedThisOutage { return .none }
            return .wait(ms: graceMs)
        case .failed:
            inOutage = true
            return tryRestart()
        default:
            return .none
        }
    }

    /// The grace period after `disconnected` ran out without recovery.
    public mutating func onGraceElapsed() -> IceAction {
        inOutage ? tryRestart() : .none
    }

    /// The restart deadline ran out; `stillDown` is the state at that moment.
    public func onRestartDeadline(stillDown: Bool) -> IceAction {
        stillDown ? .giveUp(reason: "restart-timeout") : .none
    }
}
