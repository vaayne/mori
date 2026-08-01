import XCTest
@testable import MoriRemoteTerminal

final class GhosttyTopLevelSurfaceTests: XCTestCase {
    func testPreservesOrderedLeafIDsAndValidFocus() {
        let first = UUID()
        let second = UUID()
        let third = UUID()

        let topLevel = GhosttyTopLevelSurface(
            leafIDs: [first, second, third],
            focusedLeafID: third
        )

        XCTAssertEqual(topLevel.leafIDs, [first, second, third])
        XCTAssertEqual(topLevel.focusedLeafID, third)
        XCTAssertEqual(topLevel.resolvedFocusedLeafID, third)
    }

    func testResolvedFocusFallsBackToFirstLeaf() {
        let first = UUID()
        let second = UUID()
        let topLevel = GhosttyTopLevelSurface(leafIDs: [first, second])

        XCTAssertNil(topLevel.focusedLeafID)
        XCTAssertEqual(topLevel.resolvedFocusedLeafID, first)
    }

    func testInitializerNormalizesMissingFocus() {
        let first = UUID()
        let missing = UUID()

        let topLevel = GhosttyTopLevelSurface(
            leafIDs: [first],
            focusedLeafID: missing
        )

        XCTAssertNil(topLevel.focusedLeafID)
        XCTAssertEqual(topLevel.resolvedFocusedLeafID, first)
    }

    func testEmptyTopLevelHasNoResolvedFocus() {
        let topLevel = GhosttyTopLevelSurface(leafIDs: [])

        XCTAssertNil(topLevel.focusedLeafID)
        XCTAssertNil(topLevel.resolvedFocusedLeafID)
    }
}
