import Foundation
import MoriCore

/// A project and its worktrees, stored as a single nested entry.
public struct ProjectEntry: Codable, Sendable {
    public var project: Project
    public var worktrees: [Worktree]

    public init(project: Project, worktrees: [Worktree] = []) {
        self.project = project
        self.worktrees = worktrees
    }
}

/// Top-level data structure persisted to JSON.
public struct StoreData: Codable, Sendable {
    public var projects: [ProjectEntry]
    public var uiState: UIState

    public init(
        projects: [ProjectEntry] = [],
        uiState: UIState = UIState()
    ) {
        self.projects = projects
        self.uiState = uiState
    }
}

/// Thread-safe JSON file store. Reads on init, writes atomically on mutation.
public final class JSONStore: Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private nonisolated(unsafe) var _data: StoreData

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self._data = Self.load(from: fileURL)
    }

    /// In-memory store for testing (no file I/O).
    public convenience init() {
        self.init(data: StoreData())
    }

    /// In-memory store with pre-loaded data (for testing).
    init(data: StoreData) {
        self.fileURL = URL(fileURLWithPath: "/dev/null")
        self._data = data
    }

    // MARK: - Read

    public var data: StoreData {
        lock.lock()
        defer { lock.unlock() }
        return _data
    }

    // MARK: - Write

    /// Mutate the store data and persist to disk.
    public func mutate(_ transform: (inout StoreData) -> Void) {
        lock.lock()
        transform(&_data)
        let snapshot = _data
        lock.unlock()
        Self.save(snapshot, to: fileURL)
    }

    // MARK: - File I/O

    private static func load(from url: URL) -> StoreData {
        guard let data = try? Data(contentsOf: url) else {
            return StoreData()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(StoreData.self, from: data)) ?? StoreData()
    }

    private static func save(_ storeData: StoreData, to url: URL) {
        guard url.path != "/dev/null" else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(storeData) else { return }

        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
