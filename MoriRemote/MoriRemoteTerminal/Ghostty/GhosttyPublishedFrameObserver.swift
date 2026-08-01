import QuartzCore

@MainActor
protocol GhosttyInteractionStateRefreshing: AnyObject {
    func refreshInteractionState()
}

extension GhosttyManagedSurface: GhosttyInteractionStateRefreshing {}

/// Ghostty publishes renderer-complete frames by replacing the renderer
/// sublayer's contents. Scrollbar state is authoritative only after that
/// publication; polling immediately after terminalChanged can observe the
/// previous frame and permanently under-size the local scroll document.
@MainActor
final class GhosttyPublishedFrameObserver {
    private final class Target: @unchecked Sendable {
        weak var value: (any GhosttyInteractionStateRefreshing)?
        init(_ value: any GhosttyInteractionStateRefreshing) { self.value = value }
    }

    private var observation: NSKeyValueObservation?

    func observe(_ layer: CALayer, target: any GhosttyInteractionStateRefreshing) {
        invalidate()
        let target = Target(target)
        observation = layer.observe(\.contents, options: [.new]) { _, _ in
            DispatchQueue.main.async { target.value?.refreshInteractionState() }
        }
    }

    func invalidate() {
        observation?.invalidate()
        observation = nil
    }

    deinit {
        observation?.invalidate()
    }
}
