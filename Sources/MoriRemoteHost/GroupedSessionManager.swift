import Foundation
import MoriTmux

/// Manages grouped tmux sessions created for interactive remote mode.
///
/// When a viewer connects in interactive mode, we create a grouped session
/// (`tmux new-session -t <target>`) so the iOS client gets independent window
/// sizing without constraining the Mac terminal. These sessions must be cleaned
/// up when the viewer disconnects or on periodic GC.
actor GroupedSessionManager {

    /// Prefix for grouped session names to distinguish them from user sessions.
    static let groupedPrefix = "_mori_remote_"

    /// Tracks grouped sessions: grouped session name -> target session name.
    private var activeSessions: [String: GroupedSessionInfo] = [:]

    /// GC interval: how often to check for stale sessions.
    private static let gcInterval: TimeInterval = 60.0

    /// GC task handle.
    private var gcTask: Task<Void, Never>?

    private let runner = TmuxCommandRunner()

    struct GroupedSessionInfo {
        let targetSession: String
        let createdAt: Date
    }

    // MARK: - Session Lifecycle

    /// Create a grouped session targeting an existing session.
    /// Returns the name of the new grouped session.
    func createGroupedSession(target: String) async throws -> String {
        let groupedName = "\(Self.groupedPrefix)\(target)_\(UUID().uuidString.prefix(8))"

        // tmux new-session -d -t <target> -s <grouped-name>
        // This creates a session that shares windows with the target.
        _ = try await runner.run(
            "new-session", "-d", "-t", target, "-s", groupedName
        )

        activeSessions[groupedName] = GroupedSessionInfo(
            targetSession: target,
            createdAt: Date()
        )

        // Start GC if not running
        startGCIfNeeded()

        print("[GroupedSessionManager] Created grouped session: \(groupedName) -> \(target)")
        return groupedName
    }

    /// Clean up all grouped sessions targeting a specific session.
    func cleanupGroupedSessions(for targetSession: String) async {
        let toCleanup = activeSessions.filter { $0.value.targetSession == targetSession }

        for (name, _) in toCleanup {
            await killGroupedSession(name: name)
        }
    }

    /// Clean up a specific grouped session.
    func cleanupGroupedSession(name: String) async {
        await killGroupedSession(name: name)
    }

    /// Clean up ALL grouped sessions (e.g., on host shutdown).
    func cleanupAll() async {
        let allNames = Array(activeSessions.keys)
        for name in allNames {
            await killGroupedSession(name: name)
        }
        stopGC()
    }

    /// Get the count of active grouped sessions.
    func activeCount() -> Int {
        activeSessions.count
    }

    // MARK: - Garbage Collection

    /// Start periodic GC if not already running.
    private func startGCIfNeeded() {
        guard gcTask == nil else { return }
        gcTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.gcInterval))
                guard !Task.isCancelled else { break }
                await self?.performGC()
            }
        }
    }

    /// Stop the GC task.
    private func stopGC() {
        gcTask?.cancel()
        gcTask = nil
    }

    /// Perform garbage collection: remove grouped sessions that are no longer
    /// attached to any tmux client or whose target session no longer exists.
    private func performGC() async {
        guard !activeSessions.isEmpty else {
            stopGC()
            return
        }

        // Get the list of currently running tmux sessions
        let currentSessions: Set<String>
        do {
            let output = try await runner.run(
                "list-sessions", "-F", "#{session_name}"
            )
            currentSessions = Set(
                output.split(separator: "\n").map(String.init)
            )
        } catch {
            return
        }

        var stale: [String] = []

        for (groupedName, info) in activeSessions {
            // If the grouped session no longer exists in tmux, remove tracking
            if !currentSessions.contains(groupedName) {
                stale.append(groupedName)
                continue
            }

            // If the target session no longer exists, kill the grouped session
            if !currentSessions.contains(info.targetSession) {
                stale.append(groupedName)
                continue
            }

            // Check if anyone is attached to this grouped session
            do {
                let output = try await runner.run(
                    "list-clients", "-t", groupedName, "-F", "#{client_name}"
                )
                if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // No clients attached — stale
                    stale.append(groupedName)
                }
            } catch {
                // Session might have been killed externally
                stale.append(groupedName)
            }
        }

        for name in stale {
            await killGroupedSession(name: name)
        }

        // Stop GC if no more sessions to track
        if activeSessions.isEmpty {
            stopGC()
        }
    }

    // MARK: - Private

    private func killGroupedSession(name: String) async {
        activeSessions.removeValue(forKey: name)
        do {
            _ = try await runner.run("kill-session", "-t", name)
            print("[GroupedSessionManager] Killed grouped session: \(name)")
        } catch {
            // Session might already be dead — that's fine
        }
    }
}
