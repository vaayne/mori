import XCTest
@testable import MoriRemoteTerminal

final class GhosttyTerminalSurfaceInteractionOutcomeTests: XCTestCase {
    func testFocusedTerminalInputSubmissionAcceptedStates() {
        XCTAssertTrue(FocusedTerminalInputSubmissionResult.accepted.isAccepted)
        XCTAssertTrue(FocusedTerminalInputSubmissionResult.empty.isAccepted)
        XCTAssertFalse(FocusedTerminalInputSubmissionResult.noFocusedSurface.isAccepted)
        XCTAssertFalse(FocusedTerminalInputSubmissionResult.transportUnavailable.isAccepted)
        XCTAssertFalse(FocusedTerminalInputSubmissionResult.surfaceRejected.isAccepted)
    }

    func testFocusedTerminalInputSubmissionDescriptions() {
        let cases: [(FocusedTerminalInputSubmissionResult, String)] = [
            (.accepted, "accepted"),
            (.empty, "empty"),
            (.noFocusedSurface, "noFocusedSurface"),
            (.transportUnavailable, "transportUnavailable"),
            (.surfaceRejected, "surfaceRejected"),
        ]

        for (result, description) in cases {
            XCTAssertEqual(result.description, description)
        }
    }

    func testMouseInputSubmissionSentState() {
        let missingTarget = UUID()

        XCTAssertTrue(GhosttyMouseInputSubmissionOutcome.sent.isSent)
        XCTAssertFalse(GhosttyMouseInputSubmissionOutcome.noFocusedSurface.isSent)
        XCTAssertFalse(GhosttyMouseInputSubmissionOutcome.missingTarget(missingTarget).isSent)
        XCTAssertFalse(GhosttyMouseInputSubmissionOutcome.transportUnavailable.isSent)
        XCTAssertFalse(GhosttyMouseInputSubmissionOutcome.surfaceRejected.isSent)
    }

}
