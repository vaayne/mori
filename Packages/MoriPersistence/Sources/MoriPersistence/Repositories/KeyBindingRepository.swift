import Foundation
import MoriCore

/// Sparse JSON file store for user key binding overrides.
///
/// Only user-overridden bindings are persisted. The file is a JSON dictionary
/// keyed by binding ID, with `KeyBinding` values. Missing or corrupt files
/// gracefully fall back to an empty dictionary.
public final class KeyBindingRepository: KeyBindingStorageProtocol, Sendable {
    private let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    // MARK: - KeyBindingStorageProtocol

    public func loadOverrides() -> [String: KeyBinding] {
        lock.lock()
        defer { lock.unlock() }
        return Self.load(from: fileURL)
    }

    public func saveOverrides(_ overrides: [String: KeyBinding]) {
        lock.lock()
        defer { lock.unlock() }
        Self.save(overrides, to: fileURL)
    }

    // MARK: - File I/O

    private static func load(from url: URL) -> [String: KeyBinding] {
        guard let data = try? Data(contentsOf: url) else {
            return [:]
        }
        let decoder = JSONDecoder()
        return (try? decoder.decode([String: KeyBinding].self, from: data)) ?? [:]
    }

    private static func save(_ overrides: [String: KeyBinding], to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(overrides) else { return }

        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
