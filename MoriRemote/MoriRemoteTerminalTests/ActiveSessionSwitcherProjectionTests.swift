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

    func testItemsSortUnopenedHostSessionsByName() {
        let zeta = item(name: "zeta", selected: false, opened: 0)
        let alpha = item(name: "alpha", selected: false, opened: 0)
        XCTAssertEqual(ActiveSessionSwitcherProjection.items([zeta, alpha]).map(\.sessionName), ["alpha", "zeta"])
    }

    private func item(name: String, selected: Bool, opened: TimeInterval) -> ActiveSessionSwitcherItem {
        .init(
            id: UUID(),
            sessionName: name,
            subtitle: "Mori",
            isSelected: selected,
            lastOpenedAt: Date(timeIntervalSince1970: opened)
        )
    }
}
