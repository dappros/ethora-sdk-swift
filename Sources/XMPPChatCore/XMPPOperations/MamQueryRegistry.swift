//
//  MamQueryRegistry.swift
//  XMPPChatCore
//
//  Awaits the answers to MAM queries that a caller needs as a result (a jump
//  window, a time lookup). Result messages and the closing <fin> are routed here
//  by query id. A query that is refused, fails or gets no answer in time resolves
//  with `fin == nil`, so a caller always gets an answer and never hangs.
//

import Foundation

public final class MamQueryRegistry {

    /// What one awaited MAM query returned.
    public struct PageResult {
        /// The archived messages, in the order the server sent them.
        public let messages: [Message]
        /// The closing `<fin>`, or nil when the query failed or timed out.
        public let fin: MamCursor.Fin?

        public var succeeded: Bool { fin != nil }
    }

    private final class Waiter {
        var messages: [Message] = []
        let continuation: CheckedContinuation<PageResult, Never>

        init(continuation: CheckedContinuation<PageResult, Never>) {
            self.continuation = continuation
        }
    }

    private let lock = NSLock()
    private var waiters: [String: Waiter] = [:]
    /// The `before` each page query was sent with, kept until its `<fin>`
    /// arrives, so the cursor rules can be applied to that page.
    private var requestedBefore: [String: Int64] = [:]

    public init() {}

    /// Records the `before` a paging query was sent with (nil for a latest page).
    public func noteRequest(queryId: String, before: Int64?) {
        lock.lock()
        defer { lock.unlock() }
        if let before {
            requestedBefore[queryId] = before
        } else {
            requestedBefore.removeValue(forKey: queryId)
        }
    }

    /// Returns and forgets the `before` a paging query was sent with.
    public func takeRequestedBefore(queryId: String) -> Int64? {
        lock.lock()
        defer { lock.unlock() }
        return requestedBefore.removeValue(forKey: queryId)
    }

    /// Sends a query and waits for its answer. `send` returns false when the
    /// stanza could not be sent, which resolves the wait at once as a failure.
    public func run(
        queryId: String,
        timeout: TimeInterval = 10,
        send: () -> Bool
    ) async -> PageResult {
        await withCheckedContinuation { (continuation: CheckedContinuation<PageResult, Never>) in
            lock.lock()
            waiters[queryId] = Waiter(continuation: continuation)
            lock.unlock()

            guard send() else {
                resolve(queryId: queryId, fin: nil)
                return
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.resolve(queryId: queryId, fin: nil)
            }
        }
    }

    /// Adds one archived message to the query it belongs to. Returns false when
    /// no one is waiting for that query.
    @discardableResult
    public func append(_ message: Message, queryId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let waiter = waiters[queryId] else { return false }
        waiter.messages.append(message)
        return true
    }

    /// Completes a query with its `<fin>`. Returns false when no one is waiting.
    @discardableResult
    public func complete(queryId: String, fin: MamCursor.Fin) -> Bool {
        resolve(queryId: queryId, fin: fin)
    }

    /// Completes a query as failed (IQ error). Returns false when no one is waiting.
    @discardableResult
    public func fail(queryId: String) -> Bool {
        resolve(queryId: queryId, fin: nil)
    }

    public func isWaiting(queryId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return waiters[queryId] != nil
    }

    @discardableResult
    private func resolve(queryId: String, fin: MamCursor.Fin?) -> Bool {
        lock.lock()
        let waiter = waiters.removeValue(forKey: queryId)
        lock.unlock()
        guard let waiter else { return false }
        waiter.continuation.resume(returning: PageResult(messages: waiter.messages, fin: fin))
        return true
    }
}
