//
//  P2PNegotiator.swift
//  XMPPChatCore
//
//  The pure half of the p2p signalling state machine: given the stream of
//  signals from the peer and a few "we are ready" notifications, it says WHAT
//  to do next without touching a peer connection. The controller executes the
//  commands. Mirrors src/calls/p2p/negotiator.ts.
//
//  Rules:
//   - one negotiation per callId; signals for another callId or from anyone
//     but the expected peer are ignored;
//   - the callee may get the offer before it has accepted: the first offer
//     wins, later initial offers are ignored, and it is held until markReady();
//   - candidates before the remote description are held and flushed after it;
//   - duplicates are no-ops;
//   - after the first exchange, a new offer is a renegotiation (ICE restart).
//     On glare the caller keeps its own offer, the callee yields.
//

import Foundation

public enum P2PRole: String, Equatable, Sendable {
    case caller
    case callee
}

public enum NegotiatorCommand: Equatable, Sendable {
    case applyOffer(sdp: String, initial: Bool, rollback: Bool)
    case applyAnswer(sdp: String)
    case addCandidate(P2PCandidatePayload)
    case remoteEnd(reason: String)
}

public final class P2PNegotiator {
    public static let maxHeldCandidates = 64

    public let callId: String
    public let role: P2PRole
    private let peerLocal: String

    private var ready = false
    private var ended = false
    private var remoteDescriptionSet = false
    private var initialOfferTaken = false
    private var heldOffer: String?
    private var localOfferPending = false
    private var lastOfferSdp: String?
    private var lastAnswerSdp: String?
    private var heldCandidates: [P2PCandidatePayload] = []
    private var seenCandidates = Set<String>()

    public init(callId: String, role: P2PRole, peerLocal: String) {
        self.callId = callId
        self.role = role
        self.peerLocal = (peerLocal.split(separator: "@", omittingEmptySubsequences: false).first.map(String.init) ?? "")
            .lowercased()
    }

    public var isEnded: Bool { ended }
    /// True while we have sent an offer and not yet received its answer.
    public var awaitingAnswer: Bool { localOfferPending }

    private func accepts(_ signal: P2PSignal) -> Bool {
        if ended { return false }
        if signal.callId != callId { return false }
        if !peerLocal.isEmpty, signal.fromLocal != peerLocal { return false }
        return true
    }

    public func receive(_ signal: P2PSignal) -> [NegotiatorCommand] {
        guard accepts(signal) else { return [] }

        switch signal.payload {
        case let .end(reason):
            ended = true
            heldOffer = nil
            heldCandidates = []
            return [.remoteEnd(reason: (reason ?? "").isEmpty ? "ended" : reason!)]

        case let .sdp(_, sdp):
            if signal.name == .offer {
                return receiveOffer(sdp)
            }
            // answer
            guard localOfferPending else { return [] }
            if sdp == lastAnswerSdp { return [] }
            lastAnswerSdp = sdp
            localOfferPending = false
            return [.applyAnswer(sdp: sdp)]

        case let .candidate(c):
            // An empty candidate is the end-of-candidates marker.
            if c.candidate.isEmpty { return [] }
            let key = "\(c.candidate)|\(c.sdpMid ?? "")|\(c.sdpMLineIndex.map(String.init) ?? "")"
            if seenCandidates.contains(key) { return [] }
            seenCandidates.insert(key)
            if remoteDescriptionSet { return [.addCandidate(c)] }
            if heldCandidates.count < Self.maxHeldCandidates { heldCandidates.append(c) }
            return []
        }
    }

    private func receiveOffer(_ sdp: String) -> [NegotiatorCommand] {
        if sdp == lastOfferSdp { return [] }
        if !initialOfferTaken {
            // Only the callee ever receives the first offer.
            guard role == .callee else { return [] }
            initialOfferTaken = true
            lastOfferSdp = sdp
            if !ready {
                heldOffer = sdp
                return []
            }
            return [.applyOffer(sdp: sdp, initial: true, rollback: false)]
        }
        // Renegotiation. Before the initial exchange finished, or before we
        // are ready, there is nothing to apply it to.
        guard ready, remoteDescriptionSet else { return [] }
        if localOfferPending {
            if role == .caller { return [] } // impolite: keep ours
            localOfferPending = false // polite: roll ours back
            lastOfferSdp = sdp
            return [.applyOffer(sdp: sdp, initial: false, rollback: true)]
        }
        lastOfferSdp = sdp
        return [.applyOffer(sdp: sdp, initial: false, rollback: false)]
    }

    /// Local media and the peer connection exist. Releases the offer that
    /// arrived while the callee was still on the ring screen.
    public func markReady() -> [NegotiatorCommand] {
        if ended { return [] }
        ready = true
        if let sdp = heldOffer {
            heldOffer = nil
            return [.applyOffer(sdp: sdp, initial: true, rollback: false)]
        }
        return []
    }

    /// We created and set a local offer; its answer is now expected.
    public func markLocalOffer() {
        localOfferPending = true
        lastAnswerSdp = nil
        // The caller's own first offer IS its initial exchange.
        if role == .caller { initialOfferTaken = true }
    }

    /// A remote description was applied. Returns the candidates that waited.
    public func markRemoteApplied() -> [NegotiatorCommand] {
        remoteDescriptionSet = true
        let held = heldCandidates
        heldCandidates = []
        return held.map { .addCandidate($0) }
    }

    /// Local teardown: later signals are ignored.
    public func stop() {
        ended = true
        heldOffer = nil
        heldCandidates = []
    }
}
