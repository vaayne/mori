import Foundation

#if os(macOS)

/// The main tmux integration actor. Manages scanning, session lifecycle,
/// and background polling with diff-based state updates.
public actor TmuxBackend: TmuxControlling {

    private let runner: TmuxCommandRunner

    /// Last known state from scanAll(), used for diff-based polling.
    private var lastSnapshot: [TmuxSession] = []

    /// Background polling task handle.
    private var pollingTask: Task<Void, Never>?

    /// Callback invoked when the runtime tree changes (from polling or manual scan).
    /// Called on the actor's isolation context; callers should dispatch to main if needed.
    private var onChange: (([TmuxSession]) -> Void)?

    /// Polling interval in nanoseconds (5 seconds).
    private let pollingInterval: UInt64 = 5_000_000_000

    public init(runner: TmuxCommandRunner = TmuxCommandRunner()) {
        self.runner = runner
    }

    // MARK: - Polling

    /// Set the callback to be invoked when the tmux state changes.
    public func setOnChange(_ handler: @escaping @Sendable ([TmuxSession]) -> Void) {
        self.onChange = handler
    }

    /// Start the background polling timer.
    public func startPolling() {
        guard pollingTask == nil else { return }
        let interval = self.pollingInterval
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                guard !Task.isCancelled else { break }
                guard let self = self else { break }
                await self.pollOnce()
            }
        }
    }

    /// Stop the background polling timer.
    public func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Perform a single poll: scan and notify if changed.
    /// Also exposed publicly so user actions can trigger an immediate refresh.
    public func pollOnce() async {
        do {
            let sessions = try await scanAll()
            if sessions != lastSnapshot {
                lastSnapshot = sessions
                onChange?(sessions)
            }
        } catch {
            // Polling failures are silently ignored; the next tick will retry.
        }
    }

    /// Trigger a user-action scan: scans immediately and notifies if changed.
    public func refreshNow() async {
        await pollOnce()
    }

    // MARK: - TmuxControlling (Phase 1)

    public func isAvailable() async -> Bool {
        await runner.isAvailable()
    }

    public func resolvedBinaryPath() async throws -> String {
        try await runner.resolveBinaryPath()
    }

    public func scanAll() async throws -> [TmuxSession] {
        // 1. List all sessions
        let sessionsOutput = try await runner.run(
            "list-sessions", "-F", TmuxParser.sessionFormat
        )
        var sessions = TmuxParser.parseSessions(sessionsOutput)

        // 2. For each session, list windows
        for i in sessions.indices {
            let windowsOutput = try await runner.run(
                "list-windows", "-t", sessions[i].sessionId,
                "-F", TmuxParser.windowFormat
            )
            sessions[i].windows = TmuxParser.parseWindows(windowsOutput)

            // 3. For each window, list panes
            for j in sessions[i].windows.indices {
                let target = "\(sessions[i].sessionId):\(sessions[i].windows[j].windowId)"
                let panesOutput = try await runner.run(
                    "list-panes", "-t", target,
                    "-F", TmuxParser.paneFormat
                )
                sessions[i].windows[j].panes = TmuxParser.parsePanes(panesOutput)
            }
        }

        return sessions
    }

    /// List tmux session names without deep window/pane scans.
    /// This is more resilient than `scanAll()` for connect-time checks.
    public func listSessionNames() async throws -> [String] {
        let output = try await runner.run(
            "list-sessions", "-F", "#{session_name}"
        )
        return output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0) }
    }

    /// Return the number of windows in a specific session.
    public func windowCount(sessionName: String) async throws -> Int {
        let output = try await runner.run(
            "display-message", "-p", "-t", sessionName, "#{session_windows}"
        )
        return Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    public func createSession(name: String, cwd: String) async throws -> TmuxSession {
        // Create a detached session with the given name and start directory
        let output = try await runner.run(
            "new-session", "-d", "-s", name, "-c", cwd,
            "-P", "-F", TmuxParser.sessionFormat
        )

        let sessions = TmuxParser.parseSessions(output)
        guard let session = sessions.first else {
            throw TmuxError.executionFailed(
                command: "new-session",
                exitCode: -1,
                stderr: "Failed to parse created session"
            )
        }
        return session
    }

    public func selectWindow(sessionId: String, windowId: String) async throws {
        _ = try await runner.run(
            "select-window", "-t", "\(sessionId):\(windowId)"
        )
    }

    public func killSession(id: String) async throws {
        _ = try await runner.run(
            "kill-session", "-t", id
        )
    }

    public func renameWindow(sessionId: String, windowId: String, newName: String) async throws {
        _ = try await runner.run(
            "rename-window", "-t", "\(sessionId):\(windowId)", newName
        )
    }

    public func createWindow(sessionId: String, name: String?, cwd: String?) async throws -> TmuxWindow {
        var args: [String] = ["new-window", "-t", sessionId, "-P", "-F", TmuxParser.windowFormat]
        if let name {
            args.append(contentsOf: ["-n", name])
        }
        if let cwd {
            args.append(contentsOf: ["-c", cwd])
        }
        let output = try await runner.run(args)
        let windows = TmuxParser.parseWindows(output)
        guard let window = windows.first else {
            throw TmuxError.executionFailed(
                command: "new-window",
                exitCode: -1,
                stderr: "Failed to parse created window"
            )
        }
        return window
    }

    public func sendKeys(sessionId: String, paneId: String, keys: String) async throws {
        _ = try await runner.run(
            "send-keys", "-t", "\(sessionId):\(paneId)", keys, "Enter"
        )
    }

    public func splitPane(sessionId: String, paneId: String, horizontal: Bool, cwd: String?) async throws -> TmuxPane {
        // Pane IDs like %0 are globally unique in tmux and can be used directly.
        // Fall back to session name to split the active pane in the active window.
        let target = paneId.isEmpty ? sessionId : paneId
        var args: [String] = [
            "split-window",
            horizontal ? "-h" : "-v",
            "-t", target,
            "-P", "-F", TmuxParser.paneFormat
        ]
        if let cwd {
            args.append(contentsOf: ["-c", cwd])
        }
        let output = try await runner.run(args)
        let panes = TmuxParser.parsePanes(output)
        guard let pane = panes.first else {
            throw TmuxError.executionFailed(
                command: "split-window",
                exitCode: -1,
                stderr: "Failed to parse created pane"
            )
        }
        return pane
    }

    public func killWindow(sessionId: String, windowId: String) async throws {
        _ = try await runner.run(
            "kill-window", "-t", "\(sessionId):\(windowId)"
        )
    }

    public func killPane(sessionId: String, paneId: String) async throws {
        _ = try await runner.run(
            "kill-pane", "-t", paneId
        )
    }

    public func setServerOption(option: String, value: String) async throws {
        _ = try await runner.run("set-option", "-s", option, value)
    }

    public func setOption(sessionId: String?, option: String, value: String) async throws {
        if let sessionId {
            _ = try await runner.run("set-option", "-t", sessionId, option, value)
        } else {
            // Global default (affects new sessions)
            _ = try await runner.run("set-option", "-g", option, value)
        }
    }

    /// Read an option's value lines (array options return one line per item).
    public func optionValues(sessionId: String?, option: String) async throws -> [String] {
        var args: [String] = ["show-options", "-v"]
        if let sessionId {
            args += ["-t", sessionId]
        }
        args.append(option)
        let output = try await runner.run(args)
        return output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Append an item to a tmux array/string option (`set-option -ag`).
    public func appendOptionValue(sessionId: String?, option: String, value: String) async throws {
        if let sessionId {
            _ = try await runner.run("set-option", "-ag", "-t", sessionId, option, value)
        } else {
            _ = try await runner.run("set-option", "-ag", option, value)
        }
    }

    public func setWindowOption(global: Bool, target: String?, option: String, value: String) async throws {
        if global {
            _ = try await runner.run("set-option", "-gw", option, value)
        } else if let target {
            _ = try await runner.run("set-option", "-w", "-t", target, option, value)
        }
    }

    public func capturePaneOutput(paneId: String, lineCount: Int) async throws -> String {
        try await runner.run(
            "capture-pane", "-p", "-t", paneId, "-S", "-\(lineCount)"
        )
    }

    /// Unset a pane-level user option.
    public func unsetPaneOption(paneId: String, option: String) async throws {
        _ = try await runner.run("set-option", "-pu", "-t", paneId, option)
    }

    /// Set a window-level option (targeting the window containing the given pane).
    public func setWindowOption(paneId: String, option: String, value: String) async throws {
        _ = try await runner.run("set-option", "-w", "-t", paneId, option, value)
    }

    public func navigatePane(sessionId: String, direction: PaneDirection) async throws {
        if let target = direction.selectTarget {
            // "session:.{next}" = next pane in the current window of the session
            // The dot targets the current window; {next}/{previous} targets the pane.
            _ = try await runner.run("select-pane", "-t", "\(sessionId):.\(target)")
        } else {
            _ = try await runner.run("select-pane", "-t", sessionId, "-\(direction.rawValue)")
        }
    }

    public func resizePane(sessionId: String, direction: PaneDirection, amount: Int) async throws {
        _ = try await runner.run(
            "resize-pane", "-t", sessionId, "-\(direction.rawValue)", "\(amount)"
        )
    }

    public func togglePaneZoom(sessionId: String) async throws {
        _ = try await runner.run("resize-pane", "-t", sessionId, "-Z")
    }

    public func equalizePanes(sessionId: String) async throws {
        _ = try await runner.run("select-layout", "-t", sessionId, "tiled")
    }

    public func setEnvironment(name: String, value: String) async throws {
        _ = try await runner.run("set-environment", "-g", name, value)
    }

    public func unsetEnvironment(name: String) async throws {
        _ = try await runner.run("set-environment", "-gu", name)
    }

    public func refreshClients() async throws {
        // List all connected clients and refresh each one.
        // Bare `refresh-client` with no target only works from inside a tmux session.
        let output = try await runner.run("list-clients", "-F", "#{client_name}")
        let clients = output.split(separator: "\n").map(String.init)
        for client in clients {
            _ = try? await runner.run("refresh-client", "-t", client)
        }
    }
}

#endif
