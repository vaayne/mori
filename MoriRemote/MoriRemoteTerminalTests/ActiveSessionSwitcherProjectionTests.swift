import Foundation
import XCTest
@testable import MoriRemoteTerminal

final class ActiveSessionSwitcherProjectionTests: XCTestCase {
    func testItemsPlaceSelectedSessionBeforeRecencyOrder() {
        let selected = item(name: "codex", selected: true, opened: 100)
        let recent = item(name: "api", selected: false, opened: 200)
        let older = item(name: "web", selected: false, opened: 50)

        XCTAssertEqual(
            ActiveSessionSwitcherProjection.items([recent, older, selected]).map(\.id),
            [selected.id, recent.id, older.id]
        )
    }

    private func item(name: String, selected: Bool, opened: TimeInterval) -> ActiveSessionSwitcherItem {
        .init(
            id: UUID(),
            sessionName: name,
            subtitle: "Mori",
            runtimeState: .connected,
            isSelected: selected,
            lastOpenedAt: Date(timeIntervalSince1970: opened)
        )
    }
}
