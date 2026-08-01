import XCTest
@testable import MoriRemoteTerminal

final class GhosttyImageAttachmentTests: XCTestCase {
    func testRemotePathInsertionPreservesShellExpansionAndQuotesUnsafeNames() {
        XCTAssertEqual(
            GhosttyImageTerminalPathFormatter.insertionText(for: "~/.cache/mori/image.png"),
            "~/.cache/mori/image.png"
        )
        XCTAssertEqual(
            GhosttyImageTerminalPathFormatter.insertionText(for: "~/.cache/mori/screen shot's.png"),
            #"~/'.cache/mori/screen shot'"'"'s.png'"#
        )
    }

    func testRemotePathInsertionRejectsControlCharacters() {
        XCTAssertNil(GhosttyImageTerminalPathFormatter.insertionText(for: "~/image\n.png"))
        XCTAssertNil(GhosttyImageTerminalPathFormatter.insertionText(for: ""))
    }
}
