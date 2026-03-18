import Foundation

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
}
