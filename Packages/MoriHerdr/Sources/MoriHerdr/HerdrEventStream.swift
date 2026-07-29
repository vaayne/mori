import Foundation

/// What a subscriber sees.
public enum HerdrStreamElement: Sendable {
    /// The subscription is live. herdr replays the current tree right after subscribing,
    /// so the events following this marker describe existing objects, not new ones —
    /// treat them as a fresh baseline. This is also the signal that a reconnect happened
    /// and any state accumulated from the previous connection may have gaps.
    case connected
    case event(HerdrEvent)
    /// The connection ended. The stream reconnects on its own; this is for diagnostics
    /// and for surfacing "the server went away" in the UI.
    case disconnected(reason: String)
}

/// A self-healing `events.subscribe` connection.
///
/// Two things make a raw subscription awkward to use directly, and this type exists to
/// absorb both. First, agent-status subscriptions are per-pane, so the subscription list
/// changes every time a pane appears or disappears — and herdr has no "add subscription"
/// call, only a whole new subscribe. Second, the connection can drop. Both are handled by
/// re-subscribing, which is safe precisely because herdr replays state on subscribe.
public actor HerdrEventStream {
    private let client: HerdrClient
    private let baseSubscriptions: [HerdrSubscription]
    private let reconnectDelay: (initial: Duration, maximum: Duration)

    private var watchedPanes: Set<String> = []
    private var connection: HerdrConnection?
    private var pump: Task<Void, Never>?
    private var continuation: AsyncStream<HerdrStreamElement>.Continuation?
    /// Identifies the current pump; anything from an older one is ignored.
    private var generation = 0

    public init(
        client: HerdrClient,
        subscriptions: [HerdrSubscription],
        reconnectDelay: (initial: Duration, maximum: Duration) = (.milliseconds(250), .seconds(5))
    ) {
        self.client = client
        baseSubscriptions = subscriptions
        self.reconnectDelay = reconnectDelay
    }

    /// Starts the subscription. Calling it again replaces the previous stream, ending it so
    /// its consumer unblocks rather than waiting on a stream nothing will ever feed.
    public func start() -> AsyncStream<HerdrStreamElement> {
        continuation?.finish()
        let (stream, continuation) = AsyncStream<HerdrStreamElement>.makeStream(bufferingPolicy: .unbounded)
        self.continuation = continuation
        restart()
        return stream
    }

    /// Narrows or widens the set of panes whose agent status is reported.
    ///
    /// Re-subscribes only when the set actually changes, because a re-subscribe costs a
    /// replay of the whole tree.
    public func setWatchedPanes(_ paneIDs: Set<String>) {
        guard paneIDs != watchedPanes else { return }
        watchedPanes = paneIDs
        guard continuation != nil else { return }
        restart()
    }

    public func stop() {
        generation += 1
        pump?.cancel()
        connection?.close()
        connection = nil
        pump = nil
        continuation?.finish()
        continuation = nil
    }

    // MARK: - Pump

    private func restart() {
        generation += 1
        let current = generation
        let previous = pump
        pump?.cancel()
        connection?.close()
        connection = nil
        pump = Task { [weak self] in
            await previous?.value // let the old pump unwind before opening a new socket
            await self?.run(generation: current)
        }
    }

    private func run(generation current: Int) async {
        var delay = reconnectDelay.initial
        while current == generation, !Task.isCancelled {
            let reason: String
            do {
                let connection = try await client.openSubscription(subscriptions())
                guard current == generation else {
                    connection.close()
                    return
                }
                self.connection = connection
                yield(.connected, generation: current)
                delay = reconnectDelay.initial

                while let line = try await connection.nextLine() {
                    guard current == generation else {
                        connection.close()
                        return
                    }
                    if let event = HerdrEvent.decode(line: line) {
                        yield(.event(event), generation: current)
                    }
                }
                reason = "herdr closed the event stream"
            } catch {
                reason = "\(error)"
            }
            connection?.close()
            connection = nil
            guard current == generation, !Task.isCancelled else { return }
            yield(.disconnected(reason: reason), generation: current)

            try? await Task.sleep(for: delay)
            delay = min(delay * 2, reconnectDelay.maximum)
        }
    }

    private func subscriptions() -> [HerdrSubscription] {
        baseSubscriptions + watchedPanes.sorted().map(HerdrSubscription.paneAgentStatusChanged(paneID:))
    }

    private func yield(_ element: HerdrStreamElement, generation current: Int) {
        guard current == generation else { return }
        continuation?.yield(element)
    }
}
