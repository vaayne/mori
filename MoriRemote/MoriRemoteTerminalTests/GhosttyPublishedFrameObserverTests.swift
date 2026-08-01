import QuartzCore
import XCTest
@testable import MoriRemoteTerminal

@MainActor
final class GhosttyPublishedFrameObserverTests: XCTestCase {
    func testPublishedContentsRefreshesTargetInteractionState() async {
        let layer = CALayer()
        let target = RefreshTarget()
        let observer = GhosttyPublishedFrameObserver()
        let refreshed = expectation(description: "published frame refreshes interaction state")
        target.onRefresh = { refreshed.fulfill() }
        observer.observe(layer, target: target)

        layer.contents = NSObject()

        await fulfillment(of: [refreshed], timeout: 1)
        XCTAssertEqual(target.refreshCount, 1)
    }

    func testInvalidationRejectsLaterPublications() async {
        let layer = CALayer()
        let target = RefreshTarget()
        let observer = GhosttyPublishedFrameObserver()
        let rejected = expectation(description: "invalidated observer stays silent")
        rejected.isInverted = true
        target.onRefresh = { rejected.fulfill() }
        observer.observe(layer, target: target)
        observer.invalidate()

        layer.contents = NSObject()

        await fulfillment(of: [rejected], timeout: 0.05)
        XCTAssertEqual(target.refreshCount, 0)
    }
}

@MainActor
private final class RefreshTarget: GhosttyInteractionStateRefreshing {
    var refreshCount = 0
    var onRefresh: (() -> Void)?

    func refreshInteractionState() {
        refreshCount += 1
        onRefresh?()
    }
}
