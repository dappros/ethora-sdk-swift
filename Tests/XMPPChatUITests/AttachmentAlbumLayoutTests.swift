import XCTest
@testable import XMPPChatUI

/// Layout rules for the multi-file album bubble (web helpers/albumLayout.ts).
final class AttachmentAlbumLayoutTests: XCTestCase {

    func testTwoFilesSideBySide() {
        XCTAssertEqual(AttachmentAlbumLayout.make(count: 2), .init(kind: .pair, visible: 2, hidden: 0))
    }

    func testThreeFilesHeroLayout() {
        XCTAssertEqual(AttachmentAlbumLayout.make(count: 3), .init(kind: .hero, visible: 3, hidden: 0))
    }

    func testFourFilesFillTheQuad() {
        XCTAssertEqual(AttachmentAlbumLayout.make(count: 4), .init(kind: .quad, visible: 4, hidden: 0))
    }

    func testMoreThanFourShowsFourAndCountsTheRest() {
        XCTAssertEqual(AttachmentAlbumLayout.make(count: 7), .init(kind: .quad, visible: 4, hidden: 3))
        XCTAssertEqual(AttachmentAlbumLayout.make(count: 10), .init(kind: .quad, visible: 4, hidden: 6))
    }
}
