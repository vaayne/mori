import XCTest
@testable import MoriRemoteTerminal

final class GhosttyKeyboardChromeActionsTests: XCTestCase {
    func testTerminalKeysRouteToExpectedEvents() {
        var events: [GhosttySurfaceKeyEvent] = []
        let actions = makeActions(sendKey: { events.append($0); return true })

        XCTAssertTrue(actions.perform(.escape))
        XCTAssertTrue(actions.perform(.tab))
        XCTAssertEqual(events.map(\.keyCode), [.escape, .tab])
    }

    func testSelectorsAndModifiersInvokeTheirRetainedActions() {
        var calls: [String] = []
        let actions = GhosttyKeyboardChromeActions(
            showSessions: { calls.append("sessions") },
            showWindows: { calls.append("windows") },
            showPanes: { calls.append("panes") },
            toggleKeyboard: { calls.append("keyboard") },
            toggleControl: { calls.append("control") },
            sendKey: { _ in false }
        )

        XCTAssertTrue(actions.perform(.sessions))
        XCTAssertTrue(actions.perform(.windows))
        XCTAssertTrue(actions.perform(.panes))
        XCTAssertTrue(actions.perform(.keyboard))
        XCTAssertTrue(actions.perform(.control))
        XCTAssertEqual(calls, ["sessions", "windows", "panes", "keyboard", "control"])
    }

    private func makeActions(
        sendKey: @escaping (GhosttySurfaceKeyEvent) -> Bool
    ) -> GhosttyKeyboardChromeActions {
        GhosttyKeyboardChromeActions(
            showSessions: {}, showWindows: {}, showPanes: {},
            toggleKeyboard: {}, toggleControl: {}, sendKey: sendKey
        )
    }
}
