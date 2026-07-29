import Foundation
import MoriHerdr

/// Drains a `HerdrEventStream` into a buffer so tests can wait for a specific element
/// without an iterator that has no timeout of its own.
actor EventCollector {
    private var elements: [HerdrStreamElement] = []
    private var drain: Task<Void, Never>?

    func attach(_ stream: AsyncStream<HerdrStreamElement>) {
        drain = Task { [weak self] in
            for await element in stream {
                await self?.append(element)
            }
        }
    }

    private func append(_ element: HerdrStreamElement) {
        elements.append(element)
    }

    func all() -> [HerdrStreamElement] { elements }

    func clear() { elements.removeAll() }

    /// The first buffered element matching `predicate`, or `nil` if none arrives in time.
    func first(
        matching predicate: @Sendable (HerdrStreamElement) -> Bool,
        within seconds: TimeInterval = 5
    ) async -> HerdrStreamElement? {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let match = elements.first(where: predicate) { return match }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return elements.first(where: predicate)
    }

    func detach() {
        drain?.cancel()
        drain = nil
    }
}

extension HerdrStreamElement {
    var event: HerdrEvent? {
        guard case .event(let event) = self else { return nil }
        return event
    }

    var disconnectReason: String? {
        guard case .disconnected(let reason) = self else { return nil }
        return reason
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}
