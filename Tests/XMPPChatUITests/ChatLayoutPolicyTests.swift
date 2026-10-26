import SwiftUI
import XCTest
@testable import XMPPChatUI

/// L1 tests for the tablet layout decision. The view itself needs a host
/// app to render, so only the pure policy is covered here.
final class ChatLayoutPolicyTests: XCTestCase {

    func testSideBySideOnPadAtRegularWidth() {
        XCTAssertTrue(ChatLayoutPolicy.usesSideBySide(supportsTablet: nil, isPad: true, horizontalSizeClass: .regular))
        XCTAssertTrue(ChatLayoutPolicy.usesSideBySide(supportsTablet: true, isPad: true, horizontalSizeClass: .regular))
    }

    func testStackedOnPhone() {
        XCTAssertFalse(ChatLayoutPolicy.usesSideBySide(supportsTablet: nil, isPad: false, horizontalSizeClass: .regular))
        XCTAssertFalse(ChatLayoutPolicy.usesSideBySide(supportsTablet: nil, isPad: false, horizontalSizeClass: .compact))
    }

    func testStackedOnPadInCompactSplitView() {
        XCTAssertFalse(ChatLayoutPolicy.usesSideBySide(supportsTablet: nil, isPad: true, horizontalSizeClass: .compact))
        XCTAssertFalse(ChatLayoutPolicy.usesSideBySide(supportsTablet: nil, isPad: true, horizontalSizeClass: nil))
    }

    func testHostCanTurnTabletLayoutOff() {
        XCTAssertFalse(ChatLayoutPolicy.usesSideBySide(supportsTablet: false, isPad: true, horizontalSizeClass: .regular))
    }
}
