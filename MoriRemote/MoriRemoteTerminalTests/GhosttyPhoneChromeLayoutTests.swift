import CoreGraphics
import XCTest
@testable import MoriRemoteTerminal

final class GhosttyPhoneChromeLayoutTests: XCTestCase {
    func testNarrowPortraitUsesCompactChrome() {
        let layout = GhosttyPhoneChromeLayout(screenSize: CGSize(width: 390, height: 844))
        XCTAssertTrue(layout.isCompact)
        XCTAssertEqual(layout.surfaceHorizontalPadding, 8)
        XCTAssertEqual(layout.bottomPadding, 2)
    }

    func testWidePortraitUsesExpandedChrome() {
        let layout = GhosttyPhoneChromeLayout(screenSize: CGSize(width: 430, height: 932))
        XCTAssertFalse(layout.isCompact)
        XCTAssertEqual(layout.surfaceHorizontalPadding, 12)
        XCTAssertEqual(layout.bottomPadding, 4)
    }

    func testLandscapeUsesCompactChrome() {
        let layout = GhosttyPhoneChromeLayout(screenSize: CGSize(width: 844, height: 390))
        XCTAssertTrue(layout.isLandscape)
        XCTAssertTrue(layout.isCompact)
    }

    func testBottomChromeReservationUsesFallbackThenSettledHeight() {
        var reservation = GhosttyBottomChromeReservation()
        XCTAssertEqual(reservation.layoutHeight(fallback: 52), 52)
        XCTAssertTrue(reservation.observe(renderedHeight: 91.2, isTransient: false))
        XCTAssertEqual(reservation.settledHeight, 92)
        XCTAssertFalse(reservation.observe(renderedHeight: 54, isTransient: true))
        XCTAssertEqual(reservation.settledHeight, 92)
    }
}
