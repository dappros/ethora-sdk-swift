//
//  E2EEOmemoTests.swift
//  XMPPChatCoreTests
//
//  Two OMEMO engines (alice, bob) talk through an in-memory PEP server, so device
//  publish/fetch, session setup, the room encryption and the decrypt path all run end
//  to end without a network. Also covers the stanza shapes the seams produce.
//

import XCTest
@testable import XMPPChatCore

/// Stands in for the PEP service: items per (owner, node), keyed by item id.
private final class FakePEPServer {
    var items: [String: [String: XMPPStanza]] = [:]
}

/// Transport for one account on the fake PEP server.
private final class FakePEPTransport: E2EETransport {
    let jid: String
    private let server: FakePEPServer
    private(set) var sent: [XMPPStanza] = []

    init(jid: String, server: FakePEPServer) {
        self.jid = jid
        self.server = server
    }

    func e2eeSendIQ(_ iq: XMPPStanza) async throws -> XMPPStanza {
        guard let pubsub = iq.child("pubsub") else {
            throw E2EEIQError(condition: "bad-request")
        }
        if iq.attributes["type"] == "get", let items = pubsub.child("items") {
            let owner = iq.attributes["to"] ?? jid
            let node = items.attributes["node"] ?? ""
            let stored = server.items["\(owner)|\(node)"] ?? [:]
            let wanted = items.child("item")?.attributes["id"]
            var found: [XMPPStanza]
            if let wanted {
                guard let item = stored[wanted] else { throw E2EEIQError(condition: "item-not-found") }
                found = [item]
            } else {
                found = Array(stored.values)
            }
            return XMPPStanza(name: "iq", attributes: ["type": "result"], children: [
                XMPPStanza(name: "pubsub", attributes: ["xmlns": "http://jabber.org/protocol/pubsub"], children: [
                    XMPPStanza(name: "items", attributes: ["node": node], children: found),
                ]),
            ])
        }
        if let publish = pubsub.child("publish"), let item = publish.child("item") {
            let node = publish.attributes["node"] ?? ""
            let id = item.attributes["id"] ?? ""
            server.items["\(jid)|\(node)", default: [:]][id] = item
        }
        return XMPPStanza(name: "iq", attributes: ["type": "result"])
    }

    func e2eeSend(_ stanza: XMPPStanza) {
        sent.append(stanza)
    }
}

final class E2EEOmemoTests: XCTestCase {

    private let room = "room@conference.example.com"
    private let aliceJid = "alice@example.com"
    private let bobJid = "bob@example.com"

    private func makeEngines() async throws -> (alice: E2EEOmemo, bob: E2EEOmemo) {
        let server = FakePEPServer()
        let alice = try await E2EEOmemo.create(
            transport: FakePEPTransport(jid: aliceJid, server: server),
            jid: aliceJid,
            store: E2EEMemoryKeyStore()
        )
        let bob = try await E2EEOmemo.create(
            transport: FakePEPTransport(jid: bobJid, server: server),
            jid: bobJid,
            store: E2EEMemoryKeyStore()
        )
        return (alice, bob)
    }

    private func textContent(_ text: String) -> [XMPPStanza] {
        [XMPPStanza(name: "body", text: text)]
    }

    private func dataElement() -> XMPPStanza {
        XMPPStanza(name: "data", attributes: ["senderFirstName": "Alice", "roomJid": room])
    }

    // MARK: - Round trips

    func testEncryptedRoomMessageDecryptsForRecipient() async throws {
        let (alice, bob) = try await makeEngines()
        let stanza = try await alice.encryptGroupMessage(
            roomJid: room,
            members: [bobJid],
            content: textContent("hello bob"),
            id: "m1",
            cleartext: [dataElement()]
        )

        XCTAssertEqual(stanza.name, "message")
        XCTAssertEqual(stanza.attributes["type"], "groupchat")
        XCTAssertEqual(stanza.attributes["to"], room)
        XCTAssertEqual(stanza.attributes["id"], "m1")
        XCTAssertNotNil(stanza.child("encrypted", xmlns: E2EEConstants.nsOmemo))
        XCTAssertEqual(stanza.childText("body"), E2EEConstants.fallbackBody)
        XCTAssertNotNil(stanza.child("data"), "cleartext <data> rides beside <encrypted>")
        XCTAssertEqual(stanza.child("encrypted", xmlns: E2EEConstants.nsOmemo)?.child("payload") != nil, true)

        let decrypted = try await bob.decrypt(carrier: stanza, sender: aliceJid, roomJid: room)
        XCTAssertEqual(decrypted?.content, "<body>hello bob</body>")
        XCTAssertEqual(decrypted?.trust, .blind)
        XCTAssertNil(decrypted?.error)
    }

    func testRatchetAdvancesAndRepliesFlowBothWays() async throws {
        let (alice, bob) = try await makeEngines()
        let first = try await alice.encryptGroupMessage(roomJid: room, members: [bobJid], content: textContent("one"), id: "m1")
        let second = try await alice.encryptGroupMessage(roomJid: room, members: [bobJid], content: textContent("two"), id: "m2")
        XCTAssertEqual(try await bob.decrypt(carrier: second, sender: aliceJid, roomJid: room)?.content, "<body>two</body>")
        XCTAssertEqual(try await bob.decrypt(carrier: first, sender: aliceJid, roomJid: room)?.content, "<body>one</body>")

        let reply = try await bob.encryptGroupMessage(roomJid: room, members: [aliceJid], content: textContent("reply"), id: "m3")
        XCTAssertEqual(try await alice.decrypt(carrier: reply, sender: bobJid, roomJid: room)?.content, "<body>reply</body>")

        // The room echoes our own message back. We cached the plaintext under its id.
        let echo = try await alice.decrypt(carrier: first, sender: aliceJid, roomJid: room)
        XCTAssertEqual(echo?.trust, .own)
        XCTAssertEqual(echo?.content, "<body>one</body>")
    }

    func testDecryptIsIdempotentForRepeatedDeliveries() async throws {
        let (alice, bob) = try await makeEngines()
        let stanza = try await alice.encryptGroupMessage(roomJid: room, members: [bobJid], content: textContent("again"), id: "dup")
        let a = try await bob.decrypt(carrier: stanza, sender: aliceJid, roomJid: room)
        let b = try await bob.decrypt(carrier: stanza, sender: aliceJid, roomJid: room)
        XCTAssertEqual(a?.content, "<body>again</body>")
        XCTAssertEqual(a, b)
    }

    // MARK: - Rejections

    func testReplayIntoAnotherRoomIsRejected() async throws {
        let (alice, bob) = try await makeEngines()
        let stanza = try await alice.encryptGroupMessage(roomJid: room, members: [bobJid], content: textContent("secret"), id: "r1")
        let result = try await bob.decrypt(carrier: stanza, sender: aliceJid, roomJid: "other@conference.example.com")
        XCTAssertNil(result?.content)
        XCTAssertEqual(result?.error, "omemo_decrypt_failed")
    }

    func testMessageWithoutRecipientDevicesIsNotSentInClear() async throws {
        let (alice, _) = try await makeEngines()
        do {
            _ = try await alice.encryptGroupMessage(roomJid: room, members: ["nobody@example.com"], content: textContent("x"), id: "n1")
            XCTFail("expected noRecipients")
        } catch let error as E2EEOmemoError {
            guard case .noRecipients = error else { return XCTFail("wrong error \(error)") }
        }
    }

    func testStanzaWithoutOmemoPayloadIsIgnoredByDecrypt() async throws {
        let (_, bob) = try await makeEngines()
        let plain = XMPPStanza(name: "message", attributes: ["type": "groupchat"], children: textContent("plain"))
        XCTAssertNil(try await bob.decrypt(carrier: plain, sender: aliceJid, roomJid: room))
    }

    // MARK: - Stanza seam

    func testCarrierIsFoundInsideMucsubAndMAMWrappers() throws {
        let carrier = XMPPStanza(name: "message", attributes: ["id": "x"], children: [
            XMPPStanza(name: "encrypted", attributes: ["xmlns": E2EEConstants.nsOmemo], children: [
                XMPPStanza(name: "payload", text: "AAAA"),
            ]),
        ])
        let mucsub = XMPPStanza(name: "message", children: [
            XMPPStanza(name: "event", attributes: ["xmlns": "http://jabber.org/protocol/pubsub#event"], children: [
                XMPPStanza(name: "items", children: [
                    XMPPStanza(name: "item", children: [carrier]),
                ]),
            ]),
        ])
        let path = try XCTUnwrap(E2EEStanza.carrierPath(mucsub))
        XCTAssertEqual(E2EEStanza.node(mucsub, path: path[...]).attributes["id"], "x")

        let plain = XMPPStanza(name: "message", children: [XMPPStanza(name: "body", text: "hi")])
        XCTAssertNil(E2EEStanza.carrierPath(plain))
    }

    func testDecryptInPlaceLeavesNoFallbackBodyWhenDisabled() async throws {
        // With encryption off the manager is inert: the message is rewritten to the placeholder
        // and marked as encrypted, and the OMEMO elements are gone.
        E2EERuntime.setEnabled(false)
        let (alice, _) = try await makeEngines()
        let stanza = try await alice.encryptGroupMessage(roomJid: room, members: [bobJid], content: textContent("x"), id: "p1")
        let outcome = await E2EEStanza.decryptInPlace(stanza, domain: "example.com")
        guard case .undecryptable(let rewritten) = outcome else { return XCTFail("expected undecryptable") }
        XCTAssertNil(rewritten.child("encrypted", xmlns: E2EEConstants.nsOmemo))
        XCTAssertEqual(rewritten.childText("body"), "Could not decrypt this message")
        XCTAssertEqual(rewritten.child("data")?.attributes["omemoEncrypted"], "true")
    }

    func testOutgoingEnvelopeHasNoPlaintextOnTheWire() async throws {
        let (alice, _) = try await makeEngines()
        let stanza = try await alice.encryptGroupMessage(roomJid: room, members: [bobJid], content: textContent("super-secret-text"), id: "w1")
        XCTAssertFalse(stanza.toXML().contains("super-secret-text"))
    }
}
