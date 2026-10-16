//
//  E2EEXMPPClient.swift
//  XMPPChatCore
//
//  XMPPClient as the OMEMO transport: IQ request/response correlation for PEP
//  reads and writes, and the one-way sends for encrypted stanzas. Only IQs whose id
//  carries our prefix are claimed, so every other stanza is routed exactly as before.
//

import Foundation

/// Prefix on the ids of IQs that the OMEMO engine sends and awaits.
private let e2eeIQPrefix = "e2ee-iq-"

extension XMPPClient: E2EETransport {

    func e2eeSendIQ(_ iq: XMPPStanza) async throws -> XMPPStanza {
        let id = "\(e2eeIQPrefix)\(UUID().uuidString.lowercased())"
        var request = iq
        request.attributes["id"] = id
        guard let stream = xmppStream else {
            throw E2EEIQError(condition: "not-connected")
        }
        return try await withCheckedThrowingContinuation { continuation in
            e2eeIQLock.lock()
            e2eeIQWaiters[id] = continuation
            e2eeIQLock.unlock()
            stream.send(request)
            // A reply that never comes must not leave the engine waiting forever.
            DispatchQueue.global().asyncAfter(deadline: .now() + 15) { [weak self] in
                self?.e2eeFinishIQ(id, result: .failure(E2EEIQError(condition: "timeout")))
            }
        }
    }

    func e2eeSend(_ stanza: XMPPStanza) {
        xmppStream?.send(stanza)
    }

    /// Resolves a waiting IQ when its reply arrives. Returns true when the stanza was
    /// consumed, so the caller must not route it to the chat handlers.
    func e2eeConsumeIQReply(_ stanza: XMPPStanza) -> Bool {
        guard stanza.name == "iq", let id = stanza.attributes["id"], id.hasPrefix(e2eeIQPrefix) else {
            return false
        }
        let type = stanza.attributes["type"] ?? ""
        if type == "error" {
            e2eeFinishIQ(id, result: .failure(E2EEIQError(condition: Self.iqErrorCondition(stanza))))
        } else {
            e2eeFinishIQ(id, result: .success(stanza))
        }
        return true
    }

    private func e2eeFinishIQ(_ id: String, result: Result<XMPPStanza, Error>) {
        e2eeIQLock.lock()
        let continuation = e2eeIQWaiters.removeValue(forKey: id)
        e2eeIQLock.unlock()
        continuation?.resume(with: result)
    }

    /// The stanza-error condition, e.g. "item-not-found" or "precondition-not-met".
    private static func iqErrorCondition(_ iq: XMPPStanza) -> String? {
        guard let error = iq.child("error") else { return nil }
        return error.children.first(where: { $0.name != "text" })?.name
    }
}
