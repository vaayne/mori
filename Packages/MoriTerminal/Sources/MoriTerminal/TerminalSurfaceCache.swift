import AppKit

/// LRU cache for terminal surfaces keyed by session name.
/// Keeps at most `maxSize` surfaces alive. When capacity is exceeded,
/// the least-recently-used surface is evicted via the terminal host's destroySurface().
@MainActor
public final class TerminalSurfaceCache {

    /// Cache entry tracking surface and access order.
    private struct Entry {
        let sessionName: String
        let surface: NSView
        var lastAccessed: UInt64
    }

    private let maxSize: Int
    private let terminalHost: TerminalHost
    private var entries: [String: Entry] = [:]
    private var accessCounter: UInt64 = 0

    public init(maxSize: Int = 3, terminalHost: TerminalHost) {
        self.maxSize = maxSize
        self.terminalHost = terminalHost
    }

    /// Get or create a surface for the given session.
    /// If a cached surface exists, it is returned and marked as most-recently-used.
    /// Otherwise, a new surface is created. If at capacity, the LRU surface is evicted.
    public func surface(
        forSession sessionName: String,
        command: String,
        workingDirectory: String
    ) -> NSView {
        accessCounter += 1

        // Cache hit
        if var entry = entries[sessionName] {
            entry.lastAccessed = accessCounter
            entries[sessionName] = entry
            return entry.surface
        }

        // Cache miss — evict LRU if at capacity
        if entries.count >= maxSize {
            evictLRU()
        }

        // Create new surface
        let surface = terminalHost.createSurface(
            command: command,
            workingDirectory: workingDirectory
        )

        entries[sessionName] = Entry(
            sessionName: sessionName,
            surface: surface,
            lastAccessed: accessCounter
        )

        return surface
    }

    /// Remove a specific session from the cache, destroying its surface.
    public func remove(sessionName: String) {
        guard let entry = entries.removeValue(forKey: sessionName) else { return }
        terminalHost.destroySurface(entry.surface)
    }

    /// Remove all cached surfaces.
    public func removeAll() {
        for entry in entries.values {
            terminalHost.destroySurface(entry.surface)
        }
        entries.removeAll()
    }

    /// Check if a surface is cached for the given session.
    public func contains(sessionName: String) -> Bool {
        entries[sessionName] != nil
    }

    /// Current number of cached surfaces.
    public var count: Int {
        entries.count
    }

    /// Apply current terminal host settings to all cached surfaces.
    public func applySettingsToAll() {
        for entry in entries.values {
            terminalHost.applySettings(to: entry.surface)
        }
    }

    // MARK: - Private

    private func evictLRU() {
        guard let lruKey = entries.min(by: { $0.value.lastAccessed < $1.value.lastAccessed })?.key else {
            return
        }
        remove(sessionName: lruKey)
    }
}
