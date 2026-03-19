import AppKit
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
    private var emptyStateView: NSView?

    /// Callback invoked when the user clicks the "New Session" button in the empty state.
    var onCreateSession: (() -> Void)?

    // MARK: - Init

    init(terminalHost: TerminalHost? = nil) {
        let host = terminalHost ?? GhosttyAdapter()
        self.terminalHost = host
        self.surfaceCache = TerminalSurfaceCache(maxSize: 3, terminalHost: host)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    /// Resolved theme info from ghostty's config for syncing window/sidebar appearance.
    var themeInfo: GhosttyThemeInfo {
        (terminalHost as? GhosttyAdapter)?.themeInfo ?? .fallback
    }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = themeInfo.background.cgColor
        self.view = container
        showEmptyState()
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
    ///   - sessionName: The tmux session name (e.g., "mori/main")
    ///   - workingDirectory: The worktree path for the terminal's CWD
    func attachToSession(sessionName: String, workingDirectory: String) {
        // Skip if already showing this session
        if sessionName == currentSessionName {
            focusCurrentSurface()
            return
        }

        hideEmptyState()

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

        guard surface.frame.size != .zero || view.bounds.size != .zero else {
            showError("Failed to create terminal surface for session '\(sessionName)'.")
            return
        }

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
        showEmptyState()
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

    // MARK: - Empty State

    private func showEmptyState() {
        guard emptyStateView == nil else { return }

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Terminal")
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 40, weight: .thin)
        icon.contentTintColor = .tertiaryLabelColor

        let label = NSTextField(labelWithString: "No active session")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center

        let subtitle = NSTextField(labelWithString: "Select a worktree or add a project to get started")
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .tertiaryLabelColor
        subtitle.alignment = .center

        let button = NSButton(title: "Add Project...", target: self, action: #selector(emptyStateButtonClicked))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.controlSize = .large

        container.addSubview(icon)
        container.addSubview(label)
        container.addSubview(subtitle)
        container.addSubview(button)

        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            icon.bottomAnchor.constraint(equalTo: label.topAnchor, constant: -12),

            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -16),

            subtitle.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            subtitle.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 4),

            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 16),
        ])

        view.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        emptyStateView = container
    }

    private func hideEmptyState() {
        emptyStateView?.removeFromSuperview()
        emptyStateView = nil
    }

    @objc private func emptyStateButtonClicked() {
        onCreateSession?()
    }

    // MARK: - Helpers

    private func shellEscape(_ str: String) -> String {
        "'" + str.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func showError(_ message: String) {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = "Terminal Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }
}
