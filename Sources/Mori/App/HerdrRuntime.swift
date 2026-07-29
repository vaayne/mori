import Foundation
import MoriCore
import MoriHerdr
import MoriIPC

/// Mori's herdr installation: where the binary is, which session and config file are ours,
/// and the server that has to be alive before anything else works.
///
/// Everything that needs to talk to herdr goes through here, so the answer to "which server,
/// with which config" is defined once. The config and log live beside Mori's other state in
/// Application Support, which also keeps dev builds isolated from the installed app.
@MainActor
final class HerdrRuntime {
    /// The name Mori's own session goes by. Never `default` — that one is the user's, and
    /// Mori's chrome-off config would make herdr useless as a standalone tool.
    static let sessionName = HerdrEnvironment.defaultSession

    let binaryPath: String
    let environment: HerdrEnvironment
    let controller: HerdrServerController
    let backend: HerdrBackend

    private var supervisionObserver: Task<Void, Never>?

    /// `nil` when herdr is not installed — the caller is expected to tell the user how to fix
    /// that rather than limp along.
    init?() {
        guard let resolved = BinaryResolver.resolveTool(command: "herdr") else { return nil }
        binaryPath = resolved
        environment = HerdrEnvironment(
            session: Self.sessionName,
            configPath: MoriPaths.fileURL(for: "herdr-config.toml").path
        )
        controller = HerdrServerController(
            binaryPath: resolved,
            environment: environment,
            logPath: MoriPaths.fileURL(for: "herdr-server.log").path
        )
        backend = HerdrBackend(socketPath: environment.socketPath)
    }

    /// Whether herdr is installed at all, for the startup check that decides between running
    /// and showing the install instructions.
    static var isInstalled: Bool {
        BinaryResolver.resolveTool(command: "herdr") != nil
    }

    /// Writes Mori's config and makes sure a server is up. Safe to call more than once.
    ///
    /// The config is written before the server starts so the very first client already sees
    /// the chrome turned off, rather than flashing herdr's sidebar on first paint.
    @discardableResult
    func start() async throws -> HerdrServerInfo {
        try HerdrConfigWriter.write(HerdrConfig(), to: environment.configPath)
        let info = try await controller.ensureRunning()
        await controller.startSupervision()
        return info
    }

    /// The shell command that runs herdr's client for Mori's session.
    ///
    /// Mori hosts the *full* client rather than `herdr terminal attach`: only the foreground
    /// client gets mouse reporting and kitty graphics, and a direct-attach client is never
    /// the foreground one. The chrome that comes with it is turned off in `HerdrConfig`.
    var clientCommand: String {
        (environment.shellExports.map { $0 + ";" } + ["exec \(shellQuoted(binaryPath))"]).joined(separator: " ")
    }

    /// Makes the worktree's workspace the focused one, creating it the first time.
    ///
    /// This is how selecting a worktree works now: one surface per endpoint, and switching
    /// is a `workspace.focus` on the server rather than swapping terminal surfaces. herdr
    /// addresses workspaces by opaque id, so Mori's `<project>/<branch>` identity lives in
    /// the label and is resolved on every switch.
    @discardableResult
    func revealWorkspace(label: String, cwd: String) async throws -> HerdrWorkspace {
        if let existing = try await backend.workspace(labeled: label) {
            if !existing.focused {
                try await backend.focusWorkspace(id: existing.workspaceID)
            }
            return existing
        }
        return try await backend.createWorkspace(cwd: cwd, label: label, focus: true).workspace
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// Runs `body` whenever the server's health changes, so the terminal surface can reattach
    /// after a restart.
    func observeServerState(_ body: @escaping @MainActor (HerdrServerState) -> Void) {
        supervisionObserver?.cancel()
        let controller = controller
        supervisionObserver = Task { @MainActor in
            for await state in await controller.states() {
                body(state)
            }
        }
    }

    /// Stops watching. The server itself keeps running on purpose: quitting Mori must not
    /// kill the user's shells, exactly as quitting it never killed their tmux server.
    func shutdown() {
        supervisionObserver?.cancel()
        supervisionObserver = nil
        let controller = controller
        Task { await controller.stopSupervision() }
    }
}
