import XCTest
@testable import MoriRemoteTerminal

final class GhosttyKeyboardChromeActionsTests: XCTestCase {
    func testTerminalKeysRouteToExpectedEvents() {
        var events: [GhosttySurfaceKeyEvent] = []
        let actions = makeActions(sendKey: { events.append($0); return true })

        XCTAssertTrue(actions.perform(.escape))
        XCTAssertTrue(actions.perform(.tab))
        XCTAssertTrue(actions.perform(.shiftTab))
        XCTAssertTrue(actions.perform(.arrowLeft))
        XCTAssertTrue(actions.perform(.arrowUp))
        XCTAssertTrue(actions.perform(.arrowDown))
        XCTAssertTrue(actions.perform(.arrowRight))
        XCTAssertTrue(actions.perform(.questionMark))
        XCTAssertTrue(actions.perform(.slash))
        XCTAssertEqual(events.map(\.keyCode), [.escape, .tab, .tab, .arrowLeft, .arrowUp, .arrowDown, .arrowRight, .slash, .slash])
        XCTAssertEqual(events[2].mods, .shift)
        XCTAssertEqual(events[7].text, "?")
        XCTAssertEqual(events[7].mods, .shift)
        XCTAssertEqual(events[8].text, "/")
    }

    func testSelectorsAndModifiersInvokeTheirRetainedActions() {
        var calls: [String] = []
        let actions = GhosttyKeyboardChromeActions(
            showSessions: { calls.append("sessions") },
            showWindows: { calls.append("windows") },
            showPanes: { calls.append("panes") },
            toggleKeyboard: { calls.append("keyboard") },
            toggleControl: { calls.append("control") },
            toggleAlt: { calls.append("alt") },
            sendKey: { _ in false }
        )

        XCTAssertTrue(actions.perform(.sessions))
        XCTAssertTrue(actions.perform(.windows))
        XCTAssertTrue(actions.perform(.panes))
        XCTAssertTrue(actions.perform(.keyboard))
        XCTAssertTrue(actions.perform(.control))
        XCTAssertTrue(actions.perform(.alt))
        XCTAssertEqual(calls, ["sessions", "windows", "panes", "keyboard", "control", "alt"])
    }

    private func makeActions(
        sendKey: @escaping (GhosttySurfaceKeyEvent) -> Bool
    ) -> GhosttyKeyboardChromeActions {
        GhosttyKeyboardChromeActions(
            showSessions: {}, showWindows: {}, showPanes: {},
            toggleKeyboard: {}, toggleControl: {}, toggleAlt: {}, sendKey: sendKey
        )
    }
}
