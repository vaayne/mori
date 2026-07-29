import Foundation

public struct Project: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    /// Short alias used in tmux session names (e.g. "mori", "api"). User-editable.
    public var shortName: String
    public var repoRootPath: String
    public var gitCommonDir: String
    public var originURL: String?
    public var iconName: String?
    public var isFavorite: Bool
    public var isCollapsed: Bool
    public var lastActiveAt: Date?
    public var aggregateUnreadCount: Int
    public var aggregateAlertState: AlertState
    /// Where this project's git/tmux operations execute.
    /// nil is treated as `.local` for backward compatibility.
    /// Invariant: `WorkspaceManager` is the single synchronization point that keeps
    /// project/worktree endpoint locations aligned unless a worktree is intentionally
    /// assigned a different endpoint in a dedicated migration.
    public var location: WorkspaceLocation?
    /// Normalized paths of workspaces the user removed from Mori while their files
    /// still exist on disk. Consulted by workspace auto-discovery so a removed
    /// clone/plain-dir is not resurrected on the next scan. nil = legacy/empty.
    public var dismissedWorktreePaths: [String]?

    public init(
        id: UUID = UUID(),
        name: String,
        shortName: String? = nil,
        repoRootPath: String,
        gitCommonDir: String = "",
        originURL: String? = nil,
        iconName: String? = nil,
        isFavorite: Bool = false,
        isCollapsed: Bool = false,
        lastActiveAt: Date? = nil,
        aggregateUnreadCount: Int = 0,
        aggregateAlertState: AlertState = .none,
        location: WorkspaceLocation? = nil,
        dismissedWorktreePaths: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.shortName = shortName ?? Self.autoShortName(from: name)
        self.repoRootPath = repoRootPath
        self.gitCommonDir = gitCommonDir
        self.originURL = originURL
        self.iconName = iconName
        self.isFavorite = isFavorite
        self.isCollapsed = isCollapsed
        self.lastActiveAt = lastActiveAt
        self.aggregateUnreadCount = aggregateUnreadCount
        self.aggregateAlertState = aggregateAlertState
        self.location = location
        self.dismissedWorktreePaths = dismissedWorktreePaths
    }

    /// The special $HOME workspace: pinned as a single "Home" row atop the
    /// sidebar for tasks that don't belong to any repository. Identified by
    /// path so no schema change or migration is needed.
    public var isHomeWorkspace: Bool {
        guard (location ?? .local) == .local else { return false }
        let path = (repoRootPath as NSString).expandingTildeInPath
        return path == NSHomeDirectory() || path == NSHomeDirectory() + "/"
    }

    /// Auto-generate a short name from the project name.
    /// If <= 8 chars, use as-is (lowercased). Otherwise take initials of hyphen/word segments.
    public static func autoShortName(from name: String) -> String {
        let lower = name.lowercased()
        if lower.count <= 8 { return lower }
        let parts = lower.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " || $0 == "." })
        let initials = String(parts.compactMap(\.first))
        return initials.isEmpty ? String(lower.prefix(8)) : initials
    }
}
