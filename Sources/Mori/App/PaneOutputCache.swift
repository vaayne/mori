import Foundation

/// Transient in-memory cache for captured pane output.
/// Keyed by tmux pane ID with a configurable TTL (default 5 seconds).
/// Lives in the app layer — NOT in MoriCore (avoids I/O state in models).
@MainActor
final class PaneOutputCache {
    struct Entry {
        let output: String
        let fetchedAt: Date
    }

    private var entries: [String: Entry] = [:]
    private let ttl: TimeInterval

    init(ttl: TimeInterval = 5.0) {
        self.ttl = ttl
    }

    /// Get cached output for a pane ID, or nil if expired/missing.
    func get(_ paneId: String) -> String? {
        guard let entry = entries[paneId] else { return nil }
        if Date().timeIntervalSince(entry.fetchedAt) > ttl {
            entries.removeValue(forKey: paneId)
            return nil
        }
        return entry.output
    }

    /// Store captured output for a pane ID.
    func set(_ paneId: String, output: String) {
        entries[paneId] = Entry(output: output, fetchedAt: Date())
    }

    /// Remove all cached entries.
    func invalidateAll() {
        entries.removeAll()
    }
}
