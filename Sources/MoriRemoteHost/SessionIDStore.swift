import Foundation

/// Persists session IDs for reconnection across process restarts.
/// Stores in the Mori Application Support directory.
enum SessionIDStore {

    private static var storePath: String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Mori", isDirectory: true)
        return appSupport.appendingPathComponent("remote-session-id").path
    }

    /// Save a session ID to disk.
    static func save(_ sessionID: String) {
        let dir = (storePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )

        let entry = SessionIDEntry(
            sessionID: sessionID,
            savedAt: Date()
        )

        if let data = try? JSONEncoder().encode(entry) {
            try? data.write(to: URL(fileURLWithPath: storePath))
        }
    }

    /// Load a session ID from disk. Returns nil if expired or not found.
    /// - Parameter ttl: Maximum age in seconds (default 120s).
    static func load(ttl: TimeInterval = 120) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: storePath)),
              let entry = try? JSONDecoder().decode(SessionIDEntry.self, from: data) else {
            return nil
        }

        // Check TTL
        if Date().timeIntervalSince(entry.savedAt) > ttl {
            clear()
            return nil
        }

        return entry.sessionID
    }

    /// Clear the stored session ID.
    static func clear() {
        try? FileManager.default.removeItem(atPath: storePath)
    }

    private struct SessionIDEntry: Codable {
        let sessionID: String
        let savedAt: Date
    }
}
