import XCTest
@testable import XMPPChatCore

/// MAM cursor rules, the <fin> answer, the query stanza and the awaited-query registry.
/// Mirrors xmppClient.mamCursor.test.ts and the get-history query shape.
final class MamPagingTests: XCTestCase {

    private let room = "room1@conference.test"

    private func finIQ(id: String, first: String, last: String, complete: String = "false") -> XMPPStanza {
        XMPPStanza(
            name: "iq",
            attributes: ["type": "result", "id": id, "from": room],
            children: [
                XMPPStanza(name: "fin", attributes: ["xmlns": "urn:xmpp:mam:2", "complete": complete], children: [
                    XMPPStanza(name: "set", attributes: ["xmlns": "http://jabber.org/protocol/rsm"], children: [
                        XMPPStanza(name: "first", text: first),
                        XMPPStanza(name: "last", text: last),
                    ]),
                ]),
            ]
        )
    }

    private func message(_ id: String) -> Message {
        Message(id: id, user: User(id: "u1"), date: Date(), body: "hi", roomJid: room)
    }

    // MARK: - Archive ids and fin

    func testArchiveCursorThreshold() {
        XCTAssertTrue(MamCursor.isArchiveCursor(1_700_000_000_000_000))
        XCTAssertFalse(MamCursor.isArchiveCursor(1_700_000_000_000), "millisecond timestamp is not an archive id")
        XCTAssertFalse(MamCursor.isArchiveCursor(nil))
        XCTAssertEqual(MamCursor.archiveId(" 1700000000000005 "), 1_700_000_000_000_005)
        XCTAssertNil(MamCursor.archiveId("a1b2c3-uuid"))
    }

    func testParseFinReadsCompleteFirstAndLast() {
        let fin = MamCursor.parseFin(finIQ(id: "get-history:1", first: "1700000000000000", last: "1700000000000009", complete: "true"))
        XCTAssertEqual(fin, MamCursor.Fin(complete: true, first: 1_700_000_000_000_000, last: 1_700_000_000_000_009))
        XCTAssertNil(MamCursor.parseFin(XMPPStanza(name: "message")))
    }

    // MARK: - Cursor rules (web applyHistoryPageCursor)

    func testLatePageDoesNotPullTheCursorForwardPastAnOlderOne() {
        let fin = MamCursor.Fin(complete: false, first: 1_700_000_000_000_000, last: nil)
        let next = MamCursor.nextCursor(current: 1_500_000_000_000_000, before: nil, fin: fin, hadMessages: true)
        XCTAssertEqual(next, 1_500_000_000_000_000)
    }

    func testOlderPageMovesTheCursorBack() {
        let fin = MamCursor.Fin(complete: false, first: 1_600_000_000_000_000, last: nil)
        let next = MamCursor.nextCursor(current: 1_700_000_000_000_000, before: 1_700_000_000_000_000, fin: fin, hadMessages: true)
        XCTAssertEqual(next, 1_600_000_000_000_000)
    }

    func testOlderPageThatDoesNotGoBackKeepsTheCursor() {
        let fin = MamCursor.Fin(complete: false, first: 1_800_000_000_000_000, last: nil)
        XCTAssertEqual(
            MamCursor.nextCursor(current: 1_700_000_000_000_000, before: 1_700_000_000_000_000, fin: fin, hadMessages: true),
            1_700_000_000_000_000
        )
    }

    func testLatestPageSetsTheCursorForAnEmptyRoom() {
        let fin = MamCursor.Fin(complete: false, first: 1_700_000_000_000_000, last: nil)
        let next = MamCursor.nextCursor(current: 1_500_000_000_000_000, before: nil, fin: fin, hadMessages: false)
        XCTAssertEqual(next, 1_700_000_000_000_000)
    }

    /// A page of only reactions or deleted rows shows nothing, but its <first> still moves the cursor.
    func testEmptyPageKeepsTheCursor() {
        let fin = MamCursor.Fin(complete: false, first: nil, last: nil)
        XCTAssertEqual(
            MamCursor.nextCursor(current: 1_700_000_000_000_000, before: 1_700_000_000_000_000, fin: fin, hadMessages: true),
            1_700_000_000_000_000
        )
    }

    // MARK: - Query stanza

    func testLatestPageSendsEmptyBefore() {
        let stanza = MamQuery(chatJID: room, queryId: "get-history:1", max: 30).stanza()
        let query = stanza.getChild("query")
        XCTAssertEqual(query?.attributes["queryid"], "get-history:1")
        let rsm = query?.getChild("set")
        XCTAssertEqual(rsm?.getChild("max")?.text, "30")
        XCTAssertNotNil(rsm?.getChild("before"))
        XCTAssertNil(rsm?.getChild("before")?.text)
    }

    func testWindowAfterQueryHasNoBefore() {
        let stanza = MamQuery(chatJID: room, queryId: "window:1", max: 11, after: 1_700_000_000_000_004).stanza()
        let rsm = stanza.getChild("query")?.getChild("set")
        XCTAssertEqual(rsm?.getChild("after")?.text, "1700000000000004")
        XCTAssertNil(rsm?.getChild("before"))
    }

    func testTimeLookupSendsFormAndNoRsmCursor() {
        let stanza = MamQuery(chatJID: room, queryId: "window:2", max: 50, start: "2026-07-14T10:00:00.000Z", end: "2026-07-14T10:00:10.000Z").stanza()
        let query = stanza.getChild("query")
        let form = query?.getChild("x")
        XCTAssertEqual(form?.attributes["xmlns"], "jabber:x:data")
        let fieldVars = form?.children.compactMap { $0.attributes["var"] } ?? []
        XCTAssertEqual(fieldVars, ["FORM_TYPE", "start", "end"])
        let rsm = query?.getChild("set")
        XCTAssertNil(rsm?.getChild("before"))
        XCTAssertNil(rsm?.getChild("after"))
    }

    /// Round trip: the serialized iq parses back to the same query, and its fin parses back too.
    func testQueryAndFinSurviveSerializationRoundTrip() throws {
        let query = MamQuery(chatJID: room, queryId: "window:rt", max: 10, before: 1_700_000_000_000_010)
        let parsed = try XCTUnwrap(XMPPStanzaParser.parse(query.stanza().toXML()))
        XCTAssertEqual(parsed.attributes["id"], "window:rt")
        XCTAssertEqual(parsed.attributes["to"], room)
        XCTAssertEqual(parsed.getChild("query")?.attributes["queryid"], "window:rt")
        XCTAssertEqual(parsed.getChild("query")?.getChild("set")?.getChild("before")?.text, "1700000000000010")

        let fin = finIQ(id: "window:rt", first: "1700000000000001", last: "1700000000000009", complete: "true")
        let parsedFin = try XCTUnwrap(XMPPStanzaParser.parse(fin.toXML()))
        XCTAssertEqual(MamCursor.parseFin(parsedFin), MamCursor.Fin(complete: true, first: 1_700_000_000_000_001, last: 1_700_000_000_000_009))
    }

    // MARK: - Registry

    func testRegistryCollectsRowsAndResolvesOnFin() async {
        let registry = MamQueryRegistry()
        let result = await registry.run(queryId: "window:a", timeout: 5) {
            registry.append(message("1"), queryId: "window:a")
            registry.append(message("2"), queryId: "window:a")
            registry.complete(queryId: "window:a", fin: MamCursor.Fin(complete: false, first: 1, last: 2))
            return true
        }
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.messages.map(\.id), ["1", "2"])
    }

    func testRegistryFailsWhenSendFails() async {
        let registry = MamQueryRegistry()
        let result = await registry.run(queryId: "window:b", timeout: 5) { false }
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.messages.isEmpty)
        XCTAssertFalse(registry.isWaiting(queryId: "window:b"))
    }

    func testRegistryTimesOut() async {
        let registry = MamQueryRegistry()
        let result = await registry.run(queryId: "window:c", timeout: 0.05) { true }
        XCTAssertFalse(result.succeeded)
    }

    func testRegistryIqErrorResolvesAsFailed() async {
        let registry = MamQueryRegistry()
        async let result = registry.run(queryId: "window:d", timeout: 5) { true }
        // Give the waiter time to register, then refuse it as an IQ error would.
        try? await Task.sleep(nanoseconds: 50_000_000)
        registry.fail(queryId: "window:d")
        let value = await result
        XCTAssertFalse(value.succeeded)
    }

    func testRemembersRequestedBeforeUntilFin() {
        let registry = MamQueryRegistry()
        registry.noteRequest(queryId: "get-history:x", before: 1_700_000_000_000_050)
        XCTAssertEqual(registry.takeRequestedBefore(queryId: "get-history:x"), 1_700_000_000_000_050)
        XCTAssertNil(registry.takeRequestedBefore(queryId: "get-history:x"))
    }
}
