import AppKit
import MoriCore
import MoriTerminal
import MoriTmux

/// View controller that hosts terminal surfaces, one per tmux session.
/// Uses a TerminalSurfaceCache to manage an LRU pool of surfaces (max 3).
/// When a worktree is selected, it shows the corresponding terminal surface
/// running `tmux new-session -A -s <session-name>` to attach-or-create.
@MainActor
final class TerminalAreaViewController: NSViewController {

    // MARK: - Dependencies

    let terminalHost: TerminalHost
    private let surfaceCache: TerminalSurfaceCache

    // MARK: - State

    private var currentSessionKey: String?
    private var currentSurface: NSView?
    private var emptyStateView: NSView?
    private var isHandlingSurfaceExit = false
    private var isAutoReconnecting = false
    var tmuxBinaryPath: String = TmuxCommandRunner.preferredBinaryPath() ?? "tmux"

    /// Callback invoked when the user clicks the empty-state button.
    /// If a worktree is selected (dead session), this should recreate the session.
    /// If no worktree exists, this should open the add-project panel.
    var onCreateSession: (() -> Void)?

    /// Whether the empty state should show "Reconnect" (dead session) vs "Add Project" (no project).
    var hasSelectedWorktree: Bool = false

    // MARK: - Init

    init(terminalHost: TerminalHost? = nil) {
        let host = terminalHost ?? GhosttyAdapter()
        self.terminalHost = host
        self.surfaceCache = TerminalSurfaceCache(maxSize: 3, terminalHost: host)
        super.init(nibName: nil, bundle: nil)
        installSurfaceCloseObserver()
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

    /// Reload ghostty config from disk (e.g., after editing ~/.config/ghostty/config).
    func reloadConfig() {
        (terminalHost as? GhosttyAdapter)?.reloadConfig()
    }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = themeInfo.effectiveBackground.cgColor
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
    ///   - location: Local or SSH remote endpoint.
    func attachToSession(sessionName: String, workingDirectory: String, location: WorkspaceLocation = .local) {
        let sessionKey = sessionIdentityKey(sessionName: sessionName, location: location)
        isAutoReconnecting = false

        // Skip if already showing this session
        if sessionKey == currentSessionKey {
            focusCurrentSurface()
            return
        }

        hideEmptyState()

        // Remove current surface from view (but keep in cache)
        if let oldSurface = currentSurface {
            oldSurface.removeFromSuperview()
        }
        removeResidualTerminalSubviews()

        // Get or create surface from cache.
        // Use `new-session -A` to atomically attach-or-create without shell
        // fallback chains (`has-session && attach || new-session`).
        let escaped = shellEscape(sessionName)
        let escapedTmux = shellEscape(tmuxBinaryPath)
        let command: String
        let effectiveWorkingDirectory: String
        switch location {
        case .local:
            let escapedCwd = shellEscape(workingDirectory)
            command = "export STARSHIP_LOG=error; export PATH=\"/opt/homebrew/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH\"; \(escapedTmux) new-session -A -s \(escaped) -c \(escapedCwd)"
            effectiveWorkingDirectory = workingDirectory
        case .ssh(let ssh):
            let termProgram = ProcessInfo.processInfo.environment["TERM_PROGRAM"] ?? "ghostty"
            let remoteCwd = shellEscape(workingDirectory)
            let remoteTmux = "export STARSHIP_LOG=error; export TERM_PROGRAM=\(shellEscape(termProgram)); export COLORTERM=truecolor; export PATH=\"/opt/homebrew/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:/snap/bin:$PATH\"; tmux new-session -A -s \(escaped) -c \(remoteCwd)"
            var sshCommand = "ssh -tt"
            for option in sshOptionsForInteractiveTerminal(ssh) {
                sshCommand += " \(shellEscape(option))"
            }
            if let port = ssh.port {
                sshCommand += " -p \(port)"
            }
            sshCommand += " \(shellEscape(ssh.target)) \(shellEscape(remoteTmux))"
            command = sshCommand
            // Remote paths don't exist locally; use local home to avoid chdir failures.
            effectiveWorkingDirectory = NSHomeDirectory()
        }
        let surface = surfaceCache.surface(
            forSessionKey: sessionKey,
            command: command,
            workingDirectory: effectiveWorkingDirectory
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

        currentSessionKey = sessionKey
        currentSurface = surface

        // Resize to current bounds
        terminalHost.surfaceDidResize(surface, to: view.bounds.size)

        // Focus the terminal
        focusCurrentSurface()
    }

    /// Detach the current terminal surface and evict it from the cache.
    /// The dead surface can't be reused — reconnect creates a fresh one.
    func detach() {
        isAutoReconnecting = false
        if let sessionKey = currentSessionKey {
            surfaceCache.remove(sessionKey: sessionKey)
        }
        currentSurface?.removeFromSuperview()
        currentSurface = nil
        currentSessionKey = nil
        removeResidualTerminalSubviews()
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
        let reconnecting = hasSelectedWorktree && isAutoReconnecting

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Terminal")
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 40, weight: .thin)
        icon.contentTintColor = .tertiaryLabelColor

        let labelText: String
        if reconnecting {
            labelText = .localized("Reconnecting session")
        } else {
            labelText = hasSelectedWorktree ? .localized("Session ended") : .localized("No active session")
        }
        let label = NSTextField(labelWithString: labelText)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center

        let subtitleText: String
        if reconnecting {
            subtitleText = .localized("Trying to restore remote session...")
        } else {
            subtitleText = hasSelectedWorktree
                ? .localized("The terminal session has exited")
                : .localized("Select a worktree or add a project to get started")
        }
        let subtitle = NSTextField(labelWithString: subtitleText)
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .tertiaryLabelColor
        subtitle.alignment = .center

        container.addSubview(icon)
        container.addSubview(label)
        container.addSubview(subtitle)
        var button: NSButton?
        if !reconnecting {
            let buttonTitle: String = hasSelectedWorktree ? .localized("Reconnect") : .localized("Add Project...")
            let reconnectButton = NSButton(title: buttonTitle, target: self, action: #selector(emptyStateButtonClicked))
            reconnectButton.translatesAutoresizingMaskIntoConstraints = false
            reconnectButton.bezelStyle = .rounded
            reconnectButton.controlSize = .large
            container.addSubview(reconnectButton)
            button = reconnectButton
        }

        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            icon.bottomAnchor.constraint(equalTo: label.topAnchor, constant: -12),

            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -16),

            subtitle.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            subtitle.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 4),
        ])
        if let button {
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                button.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 16),
            ])
        }

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

    func beginAutoReconnect() {
        guard hasSelectedWorktree else { return }
        isAutoReconnecting = true
        hideEmptyState()
        showEmptyState()
    }

    func endAutoReconnect() {
        guard isAutoReconnecting else { return }
        isAutoReconnecting = false
        hideEmptyState()
        if currentSurface == nil {
            showEmptyState()
        }
    }

    // MARK: - Helpers

    private func shellEscape(_ str: String) -> String {
        "'" + str.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func sshOptionsForInteractiveTerminal(_ ssh: SSHWorkspaceLocation) -> [String] {
        let options = SSHCommandSupport.connectivityOptions() + SSHControlOptions.sshOptions(for: ssh)
        var filtered = SSHCommandSupport.removingBatchMode(from: options)
        // For terminal attach we prefer interactive fallback over immediate failure.
        filtered += ["-o", "BatchMode=no"]
        return filtered
    }

    private func sessionIdentityKey(sessionName: String, location: WorkspaceLocation) -> String {
        "\(location.endpointKey)|\(sessionName)"
    }

    /// Defensive cleanup in case a dead surface view was not tracked as current.
    private func removeResidualTerminalSubviews() {
        for subview in view.subviews where subview !== emptyStateView {
            if subview !== currentSurface {
                subview.removeFromSuperview()
            }
        }
    }

    private func showError(_ message: String) {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = .localized("Terminal Error")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: .localized("OK"))
        alert.beginSheetModal(for: window)
    }

    // MARK: - Surface Exit Recovery

    private func installSurfaceCloseObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGhosttySurfaceClosedNotification(_:)),
            name: .ghosttySurfaceDidClose,
            object: nil
        )
    }

    @objc private func handleGhosttySurfaceClosedNotification(_ notification: Notification) {
        handleSurfaceClosed(notification)
    }

    private func handleSurfaceClosed(_ notification: Notification) {
        guard !isHandlingSurfaceExit else { return }
        guard let userInfo = notification.userInfo,
              let userdata = userInfo["userdata"] as? UInt,
              let currentSurface else { return }

        let currentUserdata = UInt(bitPattern: Unmanaged.passUnretained(currentSurface).toOpaque())
        guard userdata == currentUserdata else { return }

        isHandlingSurfaceExit = true
        defer { isHandlingSurfaceExit = false }

        currentSurface.removeFromSuperview()

        // Remove dead surface from cache so reconnect creates a fresh process.
        if let sessionKey = currentSessionKey {
            surfaceCache.remove(sessionKey: sessionKey)
        }
        self.currentSurface = nil
        self.currentSessionKey = nil
        removeResidualTerminalSubviews()
        isAutoReconnecting = true
        showEmptyState()

        // Auto-recover when a worktree is selected (session died / ssh dropped).
        if hasSelectedWorktree {
            onCreateSession?()
        }
    }
}
