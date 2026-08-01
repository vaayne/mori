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
        XCTAssertTrue(actions.perform(.home))
        XCTAssertTrue(actions.perform(.end))
        XCTAssertTrue(actions.perform(.pageUp))
        XCTAssertTrue(actions.perform(.pageDown))
        XCTAssertTrue(actions.perform(.questionMark))
        XCTAssertTrue(actions.perform(.slash))
        XCTAssertEqual(events.map(\.keyCode), [
            .escape, .tab, .tab, .arrowLeft, .arrowUp, .arrowDown, .arrowRight,
            .home, .end, .pageUp, .pageDown, .slash, .slash,
        ])
        XCTAssertEqual(events[2].mods, .shift)
        XCTAssertEqual(events[11].text, "?")
        XCTAssertEqual(events[11].mods, .shift)
        XCTAssertEqual(events[12].text, "/")
    }

    func testSelectorsAndModifiersInvokeTheirRetainedActions() {
        var calls: [String] = []
        let actions = GhosttyKeyboardChromeActions(
            showSessions: { calls.append("sessions") },
            showLibrary: { calls.append("library") },
            showWindows: { calls.append("windows") },
            showPanes: { calls.append("panes") },
            toggleKeyboard: { calls.append("keyboard") },
            toggleControl: { calls.append("control") },
            toggleAlt: { calls.append("alt") },
            requestSharedMutation: { mutation in
                switch mutation {
                case .newWindow: calls.append("new-window")
                case .splitHorizontal: calls.append("split-horizontal")
                case .splitVertical: calls.append("split-vertical")
                case .closePane: calls.append("close-pane")
                case .closeWindow: calls.append("close-window")
                }
            },
            sendKey: { _ in false }
        )

        XCTAssertTrue(actions.perform(.sessions))
        XCTAssertTrue(actions.perform(.library))
        XCTAssertTrue(actions.perform(.windows))
        XCTAssertTrue(actions.perform(.panes))
        XCTAssertTrue(actions.perform(.keyboard))
        XCTAssertTrue(actions.perform(.control))
        XCTAssertTrue(actions.perform(.alt))
        XCTAssertTrue(actions.perform(.newWindow))
        XCTAssertTrue(actions.perform(.splitHorizontal))
        XCTAssertTrue(actions.perform(.splitVertical))
        XCTAssertTrue(actions.perform(.closePane))
        XCTAssertTrue(actions.perform(.closeWindow))
        XCTAssertEqual(calls, [
            "sessions", "library", "windows", "panes", "keyboard", "control", "alt",
            "new-window", "split-horizontal", "split-vertical", "close-pane", "close-window",
        ])
    }

    private func makeActions(
        sendKey: @escaping (GhosttySurfaceKeyEvent) -> Bool
    ) -> GhosttyKeyboardChromeActions {
        GhosttyKeyboardChromeActions(
            showSessions: {}, showLibrary: {}, showWindows: {}, showPanes: {},
            toggleKeyboard: {}, toggleControl: {}, toggleAlt: {},
            requestSharedMutation: { _ in }, sendKey: sendKey
        )
    }
}
