import AppKit
import MoriCore
import MoriTerminal
import MoriTmux

#if compiler(>=6.2)
@available(macOS 26.0, *)
private final class WorkspaceGlassBackgroundView: NSView {
    private let glassEffectView = NSGlassEffectView()
    private let tintOverlay = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        glassEffectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassEffectView)
        NSLayoutConstraint.activate([
            glassEffectView.topAnchor.constraint(equalTo: topAnchor),
            glassEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            glassEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        tintOverlay.translatesAutoresizingMaskIntoConstraints = false
        tintOverlay.wantsLayer = true
        tintOverlay.alphaValue = 0
        addSubview(tintOverlay, positioned: .above, relativeTo: glassEffectView)
        NSLayoutConstraint.activate([
            tintOverlay.topAnchor.constraint(equalTo: topAnchor),
            tintOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            tintOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            tintOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        style: NSGlassEffectView.Style,
        backgroundColor: NSColor,
        backgroundOpacity: Double,
        isKeyWindow: Bool
    ) {
        glassEffectView.style = style
        glassEffectView.tintColor = backgroundColor.withAlphaComponent(backgroundOpacity)
        updateKeyStatus(isKeyWindow, backgroundColor: backgroundColor)
    }

    func updateKeyStatus(_ isKeyWindow: Bool, backgroundColor: NSColor) {
        let tint = tintProperties(for: backgroundColor)
        tintOverlay.layer?.backgroundColor = tint.color.cgColor
        tintOverlay.alphaValue = isKeyWindow ? 0 : tint.opacity
    }

    private func tintProperties(for color: NSColor) -> (color: NSColor, opacity: CGFloat) {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        srgb.getRed(&r, green: &g, blue: &b, alpha: nil)
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let isLight = luminance >= 0.5
        let overlayOpacity: CGFloat = isLight ? 0.35 : 0.85
        return (srgb, overlayOpacity)
    }
}
#endif

/// View controller that hosts terminal surfaces, one per tmux session.
/// Uses a TerminalSurfaceCache to manage an LRU pool of surfaces (max 3).
/// When a worktree is selected, it shows the corresponding terminal surface
/// running `tmux new-session -A -s <session-name>` to attach-or-create.
@MainActor
final class TerminalAreaViewController: NSViewController {
    private var glassBackgroundView: NSView?

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
        self.view = container
        updateAppearance(themeInfo: themeInfo, isKeyWindow: true)
        showEmptyState()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // Notify the terminal host about resize
        if let surface = currentSurface {
            terminalHost.surfaceDidResize(surface, to: view.bounds.size)
        }
    }

    func updateAppearance(themeInfo: GhosttyThemeInfo, isKeyWindow: Bool) {
        view.layer?.backgroundColor = backgroundColor(for: themeInfo).cgColor
        updateGlassEffectIfNeeded(themeInfo: themeInfo, isKeyWindow: isKeyWindow)
    }

    private func backgroundColor(for themeInfo: GhosttyThemeInfo) -> NSColor {
        themeInfo.backgroundBlur.isGlassStyle ? .clear : themeInfo.effectiveBackground
    }

#if compiler(>=6.2)
    @available(macOS 26.0, *)
    private func makeGlassBackgroundView() -> WorkspaceGlassBackgroundView {
        if let glassBackgroundView = glassBackgroundView as? WorkspaceGlassBackgroundView {
            return glassBackgroundView
        }

        let glassBackgroundView = WorkspaceGlassBackgroundView()
        glassBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(glassBackgroundView, positioned: .below, relativeTo: nil)
        NSLayoutConstraint.activate([
            glassBackgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            glassBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            glassBackgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            glassBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        self.glassBackgroundView = glassBackgroundView
        return glassBackgroundView
    }
#endif

    private func updateGlassEffectIfNeeded(themeInfo: GhosttyThemeInfo, isKeyWindow: Bool) {
#if compiler(>=6.2)
        guard #available(macOS 26.0, *), let style = glassStyle(for: themeInfo) else {
            glassBackgroundView?.removeFromSuperview()
            glassBackgroundView = nil
            return
        }

        let glassBackgroundView = makeGlassBackgroundView()
        glassBackgroundView.configure(
            style: style,
            backgroundColor: themeInfo.background,
            backgroundOpacity: themeInfo.backgroundOpacity,
            isKeyWindow: isKeyWindow
        )
#endif
    }

#if compiler(>=6.2)
    @available(macOS 26.0, *)
    private func glassStyle(for themeInfo: GhosttyThemeInfo) -> NSGlassEffectView.Style? {
        switch themeInfo.backgroundBlur {
        case .macosGlassRegular:
            .regular
        case .macosGlassClear:
            .clear
        default:
            nil
        }
    }
#endif

    // MARK: - Public API

    /// Attach to a tmux session. Creates or reuses a cached terminal surface.
    /// - Parameters:
    ///   - sessionName: The tmux session name (e.g., "mori/main")
    ///   - workingDirectory: The worktree path for the terminal's CWD
    ///   - location: Local or SSH remote endpoint.
    func attachToSession(sessionName: String, workingDirectory: String, location: WorkspaceLocation = .local) {
        let sessionKey = sessionIdentityKey(sessionName: sessionName, location: location)
        let escaped = shellEscape(sessionName)
        let escapedTmux = shellEscape(tmuxBinaryPath)

        switch location {
        case .local:
            let escapedCwd = shellEscape(workingDirectory)
            let command = "export STARSHIP_LOG=error; \(escapedTmux) new-session -A -s \(escaped) -c \(escapedCwd)"
            attachSurface(identity: sessionKey, command: command, workingDirectory: workingDirectory)
        case .ssh(let ssh):
            let termProgram = ProcessInfo.processInfo.environment["TERM_PROGRAM"] ?? "ghostty"
            let remoteCwd = shellEscape(workingDirectory)
            let remoteTmux = SSHCommandSupport.remoteLoginShellCommand(
                "tmux new-session -A -s \(escaped) -c \(remoteCwd)",
                environment: [
                    "STARSHIP_LOG": "error",
                    "TERM_PROGRAM": termProgram,
                    "COLORTERM": "truecolor",
                ]
            )
            attachSurface(identity: sessionKey, command: wrappedSSHCommand(ssh: ssh, remoteCommand: remoteTmux), workingDirectory: NSHomeDirectory())
        }
    }

    /// Attach to an arbitrary terminal command in the current workspace context.
    /// Used for embedded utility tools like Yazi and Lazygit that should live in
    /// Mori's companion pane instead of opening a new tmux window.
    func attachToCommand(
        identity: String,
        command: String,
        workingDirectory: String,
        location: WorkspaceLocation = .local,
        focus: Bool = true
    ) {
        let resolvedLocalCommand = BinaryResolver.resolveTool(command: command) ?? command
        let localCommand = "export STARSHIP_LOG=error; cd \(shellEscape(workingDirectory)); exec \(shellEscape(resolvedLocalCommand))"

        switch location {
        case .local:
            attachSurface(identity: identity, command: localCommand, workingDirectory: workingDirectory, focus: focus)
        case .ssh(let ssh):
            let termProgram = ProcessInfo.processInfo.environment["TERM_PROGRAM"] ?? "ghostty"
            let remoteCommand = SSHCommandSupport.remoteLoginShellCommand(
                "cd \(shellEscape(workingDirectory)); exec \(command)",
                environment: [
                    "STARSHIP_LOG": "error",
                    "TERM_PROGRAM": termProgram,
                    "COLORTERM": "truecolor",
                ]
            )
            attachSurface(identity: identity, command: wrappedSSHCommand(ssh: ssh, remoteCommand: remoteCommand), workingDirectory: NSHomeDirectory(), focus: focus)
        }
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

    private func attachSurface(identity: String, command: String, workingDirectory: String, focus: Bool = true) {
        isAutoReconnecting = false

        if identity == currentSessionKey {
            if focus {
                focusCurrentSurface()
            }
            return
        }

        hideEmptyState()

        if let oldSurface = currentSurface {
            oldSurface.removeFromSuperview()
        }
        removeResidualTerminalSubviews()

        let surface = surfaceCache.surface(
            forSessionKey: identity,
            command: command,
            workingDirectory: workingDirectory
        )

        guard surface.frame.size != .zero || view.bounds.size != .zero else {
            showError(.localized("Failed to create embedded terminal surface."))
            return
        }

        surface.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(surface)
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: view.topAnchor),
            surface.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        currentSessionKey = identity
        currentSurface = surface
        terminalHost.surfaceDidResize(surface, to: view.bounds.size)
        if focus {
            focusCurrentSurface()
        }
    }

    private func wrappedSSHCommand(ssh: SSHWorkspaceLocation, remoteCommand: String) -> String {
        var sshCommand = "ssh -tt"
        for option in sshOptionsForInteractiveTerminal(ssh) {
            sshCommand += " \(shellEscape(option))"
        }
        if let port = ssh.port {
            sshCommand += " -p \(port)"
        }
        sshCommand += " \(shellEscape(ssh.target)) \(shellEscape(remoteCommand))"
        return sshCommand
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
