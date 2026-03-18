import AppKit
import MoriCore
import MoriTerminal

/// View controller that hosts terminal surfaces, one per tmux session.
/// Uses a TerminalSurfaceCache to manage an LRU pool of surfaces (max 3).
/// When a worktree is selected, it shows the corresponding terminal surface
/// running `tmux attach-session -t <session-name>`.
@MainActor
final class TerminalAreaViewController: NSViewController {

    // MARK: - Dependencies

    let terminalHost: TerminalHost
    private let surfaceCache: TerminalSurfaceCache

    // MARK: - State

    private var currentSessionName: String?
    private var currentSurface: NSView?

    // MARK: - Init

    init(terminalHost: TerminalHost? = nil) {
        let host = terminalHost ?? SwiftTermAdapter()
        self.terminalHost = host
        self.surfaceCache = TerminalSurfaceCache(maxSize: 3, terminalHost: host)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        let bgHex = terminalHost.settings.theme.background
        container.layer?.backgroundColor = NSColor(hex: bgHex).cgColor
        self.view = container
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // Notify the terminal host about resize
        if let surface = currentSurface {
            terminalHost.surfaceDidResize(surface, to: view.bounds.size)
        }
    }

    // MARK: - Public API

    /// Attach to a tmux session. Creates or reuses a cached terminal surface.
    /// - Parameters:
    ///   - sessionName: The tmux session name (e.g., "ws__my-project__main")
    ///   - workingDirectory: The worktree path for the terminal's CWD
    func attachToSession(sessionName: String, workingDirectory: String) {
        // Skip if already showing this session
        if sessionName == currentSessionName {
            focusCurrentSurface()
            return
        }

        // Remove current surface from view (but keep in cache)
        if let oldSurface = currentSurface {
            oldSurface.removeFromSuperview()
        }

        // Get or create surface from cache.
        // Use `has-session` to check first, avoiding tmux parsing the session
        // name as session:window when it contains special characters.
        let escaped = shellEscape(sessionName)
        let command = "tmux has-session -t \(escaped) 2>/dev/null && tmux attach-session -t \(escaped) || tmux new-session -s \(escaped)"
        let surface = surfaceCache.surface(
            forSession: sessionName,
            command: command,
            workingDirectory: workingDirectory
        )

        // Add to view hierarchy
        surface.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(surface)
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: view.topAnchor),
            surface.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        currentSessionName = sessionName
        currentSurface = surface

        // Resize to current bounds
        terminalHost.surfaceDidResize(surface, to: view.bounds.size)

        // Focus the terminal
        focusCurrentSurface()
    }

    /// Detach the current terminal surface (remove from view but keep in cache).
    func detach() {
        currentSurface?.removeFromSuperview()
        currentSurface = nil
        currentSessionName = nil
    }

    /// Focus the current terminal surface as first responder.
    func focusCurrentSurface() {
        guard let surface = currentSurface else { return }
        terminalHost.focusSurface(surface)
    }

    /// Remove all cached surfaces and clean up.
    func removeAllSurfaces() {
        detach()
        surfaceCache.removeAll()
    }

    /// Apply updated terminal settings to all cached surfaces.
    func applySettings(_ settings: TerminalSettings) {
        terminalHost.settings = settings
        surfaceCache.applySettingsToAll()

        // Update container background to match theme
        view.layer?.backgroundColor = NSColor(hex: settings.theme.background).cgColor
    }

    // MARK: - Helpers

    private func shellEscape(_ str: String) -> String {
        "'" + str.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
