import XCTest
@testable import XMPPChatCore

/// Hermetic tests for the send side of media: the `<data>` attributes of a media message, the upload route
/// selection and multipart body, and the `fileToken` carried by login and refresh responses.
@MainActor
final class MediaUploadAndStanzaTests: XCTestCase {

    private func makeData(attachments: [MessageAttachment]? = nil, caption: String? = nil) -> MediaMessageData {
        var data = MediaMessageData(
            firstName: "Ann",
            lastName: "Lee",
            walletAddress: "0xabc",
            chatName: "room1",
            createdAt: "2026-10-16T00:00:00Z",
            fileName: "stored-1.jpg",
            userId: "u1",
            isVisible: true,
            location: "https://files.example.test/1.jpg",
            mimetype: "image/jpeg",
            originalName: "one.jpg",
            size: "100",
            attachmentId: "att-1",
            roomJid: "room1@conference.test"
        )
        data.attachments = attachments
        data.caption = caption
        return data
    }

    // MARK: - Media <data> attributes

    func testSingleFileSendHasNoAttachmentsOrCaptionAttribute() {
        let attrs = XMPPOperations.mediaDataAttributes(data: makeData(), senderJID: "u1@x")
        XCTAssertNil(attrs["attachments"])
        XCTAssertNil(attrs["caption"])
        XCTAssertEqual(attrs["isMediafile"], "true")
        XCTAssertEqual(attrs["location"], "https://files.example.test/1.jpg")
    }

    func testMultiFileSendCarriesAttachmentsJSONAndKeepsFlatFieldsForFileZero() throws {
        let files = [
            MessageAttachment(attachmentId: "att-1", location: "https://files.example.test/1.jpg", mimetype: "image/jpeg"),
            MessageAttachment(attachmentId: "att-2", location: "https://files.example.test/2.pdf", mimetype: "application/pdf"),
        ]
        let attrs = XMPPOperations.mediaDataAttributes(data: makeData(attachments: files), senderJID: "u1@x")

        let parsed = MessageAttachments.parse(attrs["attachments"])
        XCTAssertEqual(parsed, files)
        XCTAssertEqual(attrs["location"], "https://files.example.test/1.jpg")
    }

    func testCaptionIsOnTheMediaMessageAndBlankCaptionIsOmitted() {
        let withCaption = XMPPOperations.mediaDataAttributes(
            data: makeData(caption: "look at this"), senderJID: "u1@x"
        )
        XCTAssertEqual(withCaption["caption"], "look at this")

        let blank = XMPPOperations.mediaDataAttributes(data: makeData(caption: "   "), senderJID: "u1@x")
        XCTAssertNil(blank["caption"])
    }

    func testSingleEntryAttachmentsListDoesNotAddTheAttribute() {
        let one = [MessageAttachment(location: "https://files.example.test/1.jpg")]
        let attrs = XMPPOperations.mediaDataAttributes(data: makeData(attachments: one), senderJID: "u1@x")
        XCTAssertNil(attrs["attachments"])
    }

    // MARK: - Upload route and body

    func testSecureUploadUrlStripsApiVersionAndAppendsV2Route() {
        let base = URL(string: "https://api.chat.ethora.com/v1")!
        XCTAssertEqual(AuthAPI.secureUploadURL(baseURL: base).absoluteString,
                       "https://api.chat.ethora.com/v2/files/secure")
    }

    func testFallbackDecisionMatchesWeb() {
        let notFound = AuthAPIError.httpError(404, "")
        XCTAssertTrue(AuthAPI.shouldFallBackToLegacyUpload(notFound))
        XCTAssertTrue(AuthAPI.shouldFallBackToLegacyUpload(URLError(.cannotFindHost)))
        XCTAssertFalse(AuthAPI.shouldFallBackToLegacyUpload(AuthAPIError.httpError(401, "")))
        XCTAssertFalse(AuthAPI.shouldFallBackToLegacyUpload(AuthAPIError.httpError(413, "")))
        XCTAssertFalse(AuthAPI.shouldFallBackToLegacyUpload(URLError(.timedOut)))
    }

    func testUploadBodySendsChatNameOnlyWhenGiven() throws {
        let file = Data("abc".utf8)
        let secure = AuthAPI.makeUploadBody(boundary: "B", fileData: file, fileName: "a.png",
                                            mimeType: "image/png", chatName: "room1")
        let legacy = AuthAPI.makeUploadBody(boundary: "B", fileData: file, fileName: "a.png",
                                            mimeType: "image/png", chatName: nil)
        let secureText = try XCTUnwrap(String(data: secure, encoding: .utf8))
        let legacyText = try XCTUnwrap(String(data: legacy, encoding: .utf8))

        XCTAssertTrue(secureText.contains("name=\"chatName\"\r\n\r\nroom1\r\n"))
        XCTAssertFalse(legacyText.contains("chatName"))
        XCTAssertTrue(secureText.contains("name=\"files\"; filename=\"a.png\""))
        XCTAssertTrue(secureText.hasSuffix("\r\n--B--\r\n"))
    }

    // MARK: - fileToken in responses

    func testLoginResponseDecodesFileTokenAndTreatsItAsOptional() throws {
        let withToken = """
        {"success":true,"token":"t","refreshToken":"r","fileToken":"ft-1",
         "user":{"_id":"u1"}}
        """
        let decoded = try JSONDecoder().decode(AuthAPI.LoginResponse.self, from: Data(withToken.utf8))
        XCTAssertEqual(decoded.fileToken, "ft-1")

        let withoutToken = """
        {"success":true,"token":"t","refreshToken":"r","user":{"_id":"u1"}}
        """
        let older = try JSONDecoder().decode(AuthAPI.LoginResponse.self, from: Data(withoutToken.utf8))
        XCTAssertNil(older.fileToken)
    }
}
