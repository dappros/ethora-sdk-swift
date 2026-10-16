import XCTest
@testable import XMPPChatCore

/// Tests for the per-viewer `ft` token on secure file URLs (web helpers/secureFileUrl.ts).
final class SecureFileURLTests: XCTestCase {

    private let secure = "https://secure-files.example.test/room/a.jpg"
    private let publicURL = "https://files.example.test/a.jpg"

    func testAppendsTokenToSecureUrl() throws {
        let result = SecureFileURL.appendingFileToken(secure, fileToken: "tok123")
        let components = try XCTUnwrap(URLComponents(string: result))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "ft" })?.value, "tok123")
        XCTAssertEqual(components.path, "/room/a.jpg")
    }

    func testReplacesExistingTokenInsteadOfDuplicating() throws {
        let stale = "https://secure-files.example.test/a.jpg?ft=old&x=1"
        let result = SecureFileURL.appendingFileToken(stale, fileToken: "new")
        let items = try XCTUnwrap(URLComponents(string: result)?.queryItems)
        XCTAssertEqual(items.filter { $0.name == "ft" }.map(\.value), ["new"])
        XCTAssertEqual(items.first(where: { $0.name == "x" })?.value, "1")
    }

    func testPublicUrlAndMissingTokenAreUnchanged() {
        XCTAssertEqual(SecureFileURL.appendingFileToken(publicURL, fileToken: "tok"), publicURL)
        XCTAssertEqual(SecureFileURL.appendingFileToken(secure, fileToken: nil), secure)
        XCTAssertEqual(SecureFileURL.appendingFileToken(secure, fileToken: ""), secure)
        XCTAssertEqual(SecureFileURL.appendingFileToken(nil, fileToken: "tok"), "")
    }

    func testRemovingTokenGivesStableIdentity() {
        let withToken = SecureFileURL.appendingFileToken(secure, fileToken: "tok")
        XCTAssertEqual(SecureFileURL.removingFileToken(withToken), secure)
    }

    func testIsSecureOnlyForSecureFilesHost() {
        XCTAssertTrue(SecureFileURL.isSecure(secure))
        XCTAssertFalse(SecureFileURL.isSecure(publicURL))
        XCTAssertFalse(SecureFileURL.isSecure("not a url"))
    }

    func testUrlHelperReturnsTokenedURLForLoading() {
        let url = SecureFileURL.url(secure, fileToken: "tok")
        XCTAssertEqual(URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "tok")
        XCTAssertNil(SecureFileURL.url("   ", fileToken: "tok"))
    }
}
