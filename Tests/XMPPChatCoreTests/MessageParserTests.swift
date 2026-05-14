import XCTest
@testable import XMPPChatCore

/// Hermetic tests for `MessageParser` — the pure XML-tree → `MessageData`
/// / `Message` mapper.
///
/// The parser sits at the heart of every inbound message path: live MUC
/// stanzas, MAM history replay, and the mucsub-wrapped variants all
/// flow through `getDataFromStanza`. A regression here silently breaks
/// chat. Pin the contract:
///   • MAM-wrapped stanzas (`result > forwarded > message`) get
///     unwrapped, and the inner `<message>` payload is what we parse.
///   • `<deleted/>` child marks a tombstone — `isDeleted` must be true
///     on the resulting `Message`.
///   • `from` parsing splits on `/` → bare JID + occupant nickname.
///   • `data` element's attributes (incl. `isMediafile`, `photoURL`,
///     `senderFirstName`, `mainMessage`, etc.) propagate through.
///   • `translations` JSON in the `<translations value="…"/>` attribute
///     is decoded into the `translations` map.
///   • Empty body is permitted (filtered out higher up in
///     `handleIncomingMessage` per the comment on
///     `createMessageFromData`).
@MainActor
final class MessageParserTests: XCTestCase {

    // MARK: - Helpers

    private func messageStanza(
        id: String = "msg-1700000000000",
        from: String = "room1@conference.test/alice",
        body: String? = "hello",
        deleted: Bool = false,
        dataAttrs: [String: String]? = nil,
        translationsJSON: String? = nil,
        stanzaId: String? = nil
    ) -> XMPPStanza {
        var children: [XMPPStanza] = []
        if let body = body {
            children.append(XMPPStanza(name: "body", text: body))
        }
        if deleted {
            children.append(XMPPStanza(name: "deleted"))
        }
        if let dataAttrs = dataAttrs {
            children.append(XMPPStanza(name: "data", attributes: dataAttrs))
        }
        if let translationsJSON = translationsJSON {
            children.append(XMPPStanza(name: "translations", attributes: ["value": translationsJSON]))
        }
        if let stanzaId = stanzaId {
            children.append(XMPPStanza(name: "stanza-id", attributes: ["id": stanzaId]))
        }
        return XMPPStanza(
            name: "message",
            attributes: ["id": id, "from": from, "type": "groupchat"],
            children: children
        )
    }

    private func mamWrap(_ inner: XMPPStanza, archiveId: String = "mam-archive-1") -> XMPPStanza {
        // `<result xmlns='urn:xmpp:mam:2'><forwarded xmlns='urn:xmpp:forward:0'><message …/></forwarded></result>`
        let forwarded = XMPPStanza(
            name: "forwarded",
            attributes: ["xmlns": "urn:xmpp:forward:0"],
            children: [inner]
        )
        let result = XMPPStanza(
            name: "result",
            attributes: ["xmlns": "urn:xmpp:mam:2", "id": archiveId],
            children: [forwarded]
        )
        return XMPPStanza(name: "message", children: [result])
    }

    // MARK: - Plain message

    func testParsesPlainMessageBodyAndSenderJID() {
        let stanza = messageStanza(
            id: "msg-1700000000123",
            from: "room1@conference.test/alice-handle",
            body: "hello world"
        )
        let parsed = MessageParser.getDataFromStanza(stanza)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.body, "hello world")
        XCTAssertEqual(parsed?.roomJid, "room1@conference.test",
                       "roomJid is the bare-JID portion before '/'")
        XCTAssertEqual(parsed?.userWallet, "alice-handle",
                       "userWallet is the resource (occupant nickname)")
        XCTAssertEqual(parsed?.xmppId, "msg-1700000000123")
        XCTAssertFalse(parsed?.deleted ?? true)
    }

    func testParsesEmptyBodyAsNilOrEmptyString() {
        // The parser permits empty-body messages — they're filtered at
        // the addRoomMessage layer (see comment on createMessageFromData).
        let stanza = messageStanza(body: nil)
        let parsed = MessageParser.getDataFromStanza(stanza)
        XCTAssertNotNil(parsed)
        XCTAssertNil(parsed?.body, "absent <body/> must read as nil — not as empty string")
    }

    // MARK: - <deleted/> tombstone marker

    func testDeletedChildElementSetsDeletedTrue() {
        let stanza = messageStanza(body: "", deleted: true)
        let parsed = MessageParser.getDataFromStanza(stanza)
        XCTAssertEqual(parsed?.deleted, true,
                       "a <deleted/> child must propagate as deleted=true")
    }

    func testCreateMessageFromDataMapsDeletedOntoIsDeleted() {
        let stanza = messageStanza(body: "", deleted: true)
        let parsed = MessageParser.getDataFromStanza(stanza)!
        let message = MessageParser.createMessageFromData(parsed)
        XCTAssertEqual(message.isDeleted, true)
    }

    // MARK: - MAM unwrap

    func testMAMResultStanzaIsUnwrappedToInnerMessage() {
        // Server-replayed history arrives wrapped:
        //   <message><result xmlns='urn:xmpp:mam:2' id='archive-id'>
        //     <forwarded xmlns='urn:xmpp:forward:0'>
        //       <message id='msg-…' from='…'><body>…</body></message>
        //     </forwarded>
        //   </result></message>
        // The parser must read body / from / data off the *inner*
        // message, and the MAM archive-id off the outer <result>.
        let inner = messageStanza(
            id: "msg-1700000000456",
            from: "room1@conference.test/bob",
            body: "from history"
        )
        let wrapped = mamWrap(inner, archiveId: "mam-archive-XYZ")

        let parsed = MessageParser.getDataFromStanza(wrapped)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.body, "from history")
        XCTAssertEqual(parsed?.roomJid, "room1@conference.test")
        XCTAssertEqual(parsed?.userWallet, "bob")
        XCTAssertEqual(parsed?.id, "mam-archive-XYZ",
                       "MAM id MUST be the <result> archive id (used for paging anchors), not the inner stanza id")
        XCTAssertEqual(parsed?.xmppId, "msg-1700000000456",
                       "xmppId still tracks the inner stanza id for dedupe / edit anchors")
    }

    // MARK: - data attributes (photo, isMediafile, sender names)

    func testDataElementAttributesPropagateToMessageData() {
        let stanza = messageStanza(
            body: "hi",
            dataAttrs: [
                "photoURL": "https://cdn.example.com/avatar.jpg",
                "senderFirstName": "Alice",
                "senderLastName": "Doe",
                "isMediafile": "false",
                "mainMessage": "{\"id\":\"original-msg\"}",
            ]
        )
        let parsed = MessageParser.getDataFromStanza(stanza)
        XCTAssertEqual(parsed?.photoURL, "https://cdn.example.com/avatar.jpg")
        XCTAssertEqual(parsed?.dataAttrs["senderFirstName"], "Alice")
        XCTAssertEqual(parsed?.dataAttrs["senderLastName"], "Doe")
        XCTAssertEqual(parsed?.dataAttrs["isMediafile"], "false")
        XCTAssertEqual(parsed?.dataAttrs["mainMessage"], "{\"id\":\"original-msg\"}")
    }

    func testPhotoURLFallsBackToPhotoAttributeWhenPhotoURLAbsent() {
        // Backend has historically sent both "photo" and "photoURL";
        // the parser picks photoURL first, then photo. Pin the fallback
        // so an older server response doesn't drop avatars on iOS.
        let stanza = messageStanza(body: "hi", dataAttrs: ["photo": "https://cdn.example.com/legacy.jpg"])
        let parsed = MessageParser.getDataFromStanza(stanza)
        XCTAssertEqual(parsed?.photoURL, "https://cdn.example.com/legacy.jpg")
    }

    func testCreateMessageFromDataHydratesUserAndMediaFields() {
        // End-to-end transform: stanza → MessageData → Message. Locks
        // the User shape and the media-field passthrough.
        let stanza = messageStanza(
            id: "msg-1700000000789",
            from: "room1@conference.test/charlie",
            body: "media",
            dataAttrs: [
                "isMediafile": "true",
                "mimetype": "image/png",
                "location": "https://cdn.example.com/pic.png",
                "fileName": "pic.png",
                "size": "12345",
                "photoURL": "https://cdn.example.com/avatar.jpg",
                "senderFirstName": "Charlie",
                "fullName": "Charlie Brown",
            ]
        )
        let parsed = MessageParser.getDataFromStanza(stanza)!
        let message = MessageParser.createMessageFromData(parsed)

        XCTAssertEqual(message.id, "msg-1700000000789")
        XCTAssertEqual(message.body, "media")
        XCTAssertEqual(message.isMediafile, "true")
        XCTAssertEqual(message.mimetype, "image/png")
        XCTAssertEqual(message.location, "https://cdn.example.com/pic.png")
        XCTAssertEqual(message.fileName, "pic.png")
        XCTAssertEqual(message.size, "12345")
        XCTAssertEqual(message.user.firstName, "Charlie")
        XCTAssertEqual(message.user.name, "Charlie Brown")
        XCTAssertEqual(message.user.profileImage, "https://cdn.example.com/avatar.jpg")
    }

    func testCreateMessageFromDataInfersMimeTypeFromLocationWhenMissing() {
        // Media-fallback rule documented in the parser: if isMediafile=true
        // but mimetype is absent or empty, infer it from the location URL
        // extension. Important because some clients drop the mimetype.
        let stanza = messageStanza(
            body: "media",
            dataAttrs: [
                "isMediafile": "true",
                "location": "https://cdn.example.com/movie.mp4",
                "mimetype": "",
            ]
        )
        let parsed = MessageParser.getDataFromStanza(stanza)!
        let message = MessageParser.createMessageFromData(parsed)
        XCTAssertEqual(message.mimetype, "video/mp4",
                       "missing mimetype must be inferred from the URL extension")
    }

    // MARK: - Translations

    func testTranslationsJSONAttributeDecodesIntoMap() {
        // The translations element carries a JSON blob in its `value`
        // attribute: `{"translates":[{"lang":"en","text":"hello"}, …]}`.
        // Decode it into a per-language map.
        let json = """
        {"translates":[{"lang":"en","text":"hello"},{"lang":"fr","text":"bonjour"}]}
        """
        let stanza = messageStanza(body: "hola", translationsJSON: json)
        let parsed = MessageParser.getDataFromStanza(stanza)
        XCTAssertEqual(parsed?.translations?["en"], "hello")
        XCTAssertEqual(parsed?.translations?["fr"], "bonjour")
    }

    func testTranslationsAbsentParsesAsNil() {
        let stanza = messageStanza(body: "hola")
        let parsed = MessageParser.getDataFromStanza(stanza)
        XCTAssertNil(parsed?.translations)
    }

    // MARK: - stanza-id fallback (non-MAM live messages with archive id)

    func testStanzaIdChildIsUsedWhenNoMAMResult() {
        // Live MUC echo / mucsub stanzas can carry a `<stanza-id id='…'/>`
        // that the server assigns when archiving. If there's no MAM
        // wrapper, the parser should use the full stanza-id as the id —
        // the React reference doesn't truncate (see getDataFromXml.ts).
        let stanza = messageStanza(
            id: "msg-1700000000999",
            from: "room1@conference.test/dave",
            body: "live with archive id",
            stanzaId: "stanza-archive-abc123"
        )
        let parsed = MessageParser.getDataFromStanza(stanza)
        XCTAssertEqual(parsed?.id, "stanza-archive-abc123",
                       "stanza-id is used in full — truncation breaks MAM <before> paging")
    }
}
