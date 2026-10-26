import XCTest
@testable import XMPPChatCore

/// Hermetic tests for the multi-file wire form: `attachments` JSON, legacy flat fields, mimetype inference,
/// and the parser entry points that feed them.
@MainActor
final class MessageAttachmentTests: XCTestCase {

    private let photoURL = "https://files.example.test/a.jpg"
    private let docURL = "https://files.example.test/b.pdf"

    // MARK: - Wire form

    func testSerializeThenParseRoundTripsEveryRenderedField() {
        let original = [
            MessageAttachment(
                attachmentId: "att-1",
                location: photoURL,
                locationPreview: "https://files.example.test/a-preview.jpg",
                mimetype: "image/jpeg",
                originalName: "holiday.jpg",
                fileName: "stored-1.jpg",
                size: "12345"
            ),
            MessageAttachment(
                attachmentId: "att-2",
                location: docURL,
                mimetype: "application/pdf",
                originalName: "report.pdf",
                fileName: "stored-2.pdf",
                size: "999"
            ),
        ]

        let wire = MessageAttachments.serialize(original)
        let parsed = MessageAttachments.parse(wire)

        XCTAssertEqual(parsed, original)
    }

    func testSerializeCapsAtMaxPerMessage() {
        let many = (0..<15).map { MessageAttachment(location: "https://files.example.test/\($0).png") }
        let parsed = MessageAttachments.parse(MessageAttachments.serialize(many))
        XCTAssertEqual(parsed.count, MessageAttachments.maxPerMessage)
    }

    func testParseAcceptsApiSpellingAndNumericSize() {
        let raw = """
        [{"location":"\(photoURL)","originalname":"x.png","filename":"s.png","size":2048,"_id":"id-9"}]
        """
        let parsed = MessageAttachments.parse(raw)

        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].originalName, "x.png")
        XCTAssertEqual(parsed[0].fileName, "s.png")
        XCTAssertEqual(parsed[0].size, "2048")
        XCTAssertEqual(parsed[0].attachmentId, "id-9")
        XCTAssertEqual(parsed[0].mimetype, "image/png", "generic mimetype is inferred from the name")
    }

    func testParseDropsEntriesWithoutLocationAndJunk() {
        let raw = #"[{"location":""},{"originalName":"no-url.png"},{"location":"\#(photoURL)"}]"#
        XCTAssertEqual(MessageAttachments.parse(raw).map(\.location), [photoURL])
        XCTAssertEqual(MessageAttachments.parse("not json"), [])
        XCTAssertEqual(MessageAttachments.parse(nil), [])
    }

    // MARK: - Legacy flat fields

    func testLegacySingleLocationIsOneAttachment() {
        let items = MessageAttachments.fromLegacyFields(
            location: photoURL,
            mimetype: "image/jpeg",
            originalName: "a.jpg"
        )
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].location, photoURL)
        XCTAssertEqual(items[0].originalName, "a.jpg")
    }

    func testLegacyCommaSeparatedUrlsSplitIntoSeveralFiles() {
        let items = MessageAttachments.fromLegacyFields(
            location: "\(photoURL), \(docURL)",
            mimetype: "image/jpeg,application/pdf",
            originalName: "a.jpg,b.pdf"
        )
        XCTAssertEqual(items.map(\.location), [photoURL, docURL])
        XCTAssertEqual(items.map(\.mimetype), ["image/jpeg", "application/pdf"])
        XCTAssertEqual(items.map(\.originalName), ["a.jpg", "b.pdf"])
    }

    func testLegacyEmptyLocationGivesNoAttachments() {
        XCTAssertEqual(MessageAttachments.fromLegacyFields(location: nil), [])
        XCTAssertEqual(MessageAttachments.fromLegacyFields(location: ""), [])
    }

    func testMessageMediaAttachmentsPrefersPayloadThenFallsBackToFlatFields() {
        let user = User(id: "u1")
        var message = Message(
            id: "m1",
            user: user,
            date: Date(),
            body: "media",
            roomJid: "room@conference.test",
            isMediafile: "true",
            mimetype: "image/jpeg",
            location: photoURL
        )
        XCTAssertEqual(message.mediaAttachments.map(\.location), [photoURL])

        message.attachments = [
            MessageAttachment(location: photoURL),
            MessageAttachment(location: docURL),
        ]
        XCTAssertEqual(message.mediaAttachments.map(\.location), [photoURL, docURL])
    }

    // MARK: - Mimetype inference

    func testResolveMimetypeReplacesGenericWithNameBasedType() {
        XCTAssertEqual(MessageAttachments.resolveMimetype("application/octet-stream", names: ["clip.mp4"]), "video/mp4")
        XCTAssertEqual(MessageAttachments.resolveMimetype(nil, names: [nil, "scan.PDF"]), "application/pdf")
        XCTAssertEqual(MessageAttachments.resolveMimetype("image/png", names: ["a.jpg"]), "image/png",
                       "a specific mimetype is kept as sent")
    }

    func testInferMimetypeIgnoresQueryAndUnknownExtensions() {
        XCTAssertEqual(MessageAttachments.inferMimetype(fromName: "https://x.test/p.webp?ft=abc"), "image/webp")
        XCTAssertNil(MessageAttachments.inferMimetype(fromName: "archive.zip"))
    }

    // MARK: - Upload mapping

    func testFromUploadMapsApiSpelledFieldsAndRequiresLocation() throws {
        let json = #"{"results":[{"_id":"id-1","filename":"stored.png","originalname":"orig.png","mimetype":"image/png","size":77,"location":"\#(photoURL)","locationPreview":"\#(photoURL)?p=1"}]}"#
        let response = try JSONDecoder().decode(UploadResponse.self, from: Data(json.utf8))
        let attachment = try XCTUnwrap(MessageAttachments.fromUpload(response.results[0]))

        XCTAssertEqual(attachment.attachmentId, "id-1")
        XCTAssertEqual(attachment.originalName, "orig.png")
        XCTAssertEqual(attachment.fileName, "stored.png")
        XCTAssertEqual(attachment.size, "77")
        XCTAssertEqual(attachment.locationPreview, "\(photoURL)?p=1")
    }
    // MARK: - Parser entry point

    func testParserReadsAttachmentsAndCaptionFromDataAttributes() throws {
        let payload = MessageAttachments.serialize([
            MessageAttachment(location: photoURL, mimetype: "image/jpeg"),
            MessageAttachment(location: docURL, mimetype: "application/pdf"),
        ])
        let stanza = XMPPStanza(
            name: "message",
            attributes: ["id": "send-media-message-1", "from": "room@conference.test/ann", "type": "groupchat"],
            children: [
                XMPPStanza(name: "body", text: "media"),
                XMPPStanza(name: "data", attributes: [
                    "isMediafile": "true",
                    "location": photoURL,
                    "mimetype": "image/jpeg",
                    "attachments": payload,
                    "caption": "two files",
                ]),
            ]
        )
        let data = try XCTUnwrap(MessageParser.getDataFromStanza(stanza))
        let message = MessageParser.createMessageFromData(data)

        XCTAssertEqual(message.mediaAttachments.map(\.location), [photoURL, docURL])
        XCTAssertEqual(message.caption, "two files")
    }

    func testParserLeavesAttachmentsNilForSingleLegacyFile() throws {
        let stanza = XMPPStanza(
            name: "message",
            attributes: ["id": "m-2", "from": "room@conference.test/ann", "type": "groupchat"],
            children: [
                XMPPStanza(name: "body", text: "media"),
                XMPPStanza(name: "data", attributes: ["isMediafile": "true", "location": photoURL, "caption": "   "]),
            ]
        )
        let message = MessageParser.createMessageFromData(try XCTUnwrap(MessageParser.getDataFromStanza(stanza)))
        XCTAssertNil(message.attachments)
        XCTAssertNil(message.caption, "a blank caption is no caption")
        XCTAssertEqual(message.mediaAttachments.map(\.location), [photoURL])
    }
}
