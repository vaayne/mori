import Foundation

/// Lists source sessions through the same authenticated root pool as terminal
/// runtimes. Discovery never creates, attaches, resizes, or switches a tmux client.
struct SSHTmuxSessionDiscovery: Sendable {
    let connector: any SSHRootConnecting
    let pool: SSHRootPool
    let poolKey: SSHRootPool.Key
    var tmuxExecutable = "tmux"

    func load() async throws -> [String] {
        let lease = try await pool.lease(for: poolKey, connector: connector)
        do {
            let version = try await run(
                command: TmuxCommandBuilder.preflight(executable: tmuxExecutable),
                root: lease.root
            )
            try TmuxCommandBuilder.requireSupportedVersion(version)
            let output = try await run(
                command: TmuxCommandBuilder.listSessions(executable: tmuxExecutable),
                root: lease.root
            )
            await lease.release(.reusable)
            return TmuxSessionList.parse(output).names
        } catch {
            await lease.release(.invalidated)
            throw error
        }
    }

    private func run(command: String, root: any SSHRootConnection) async throws -> String {
        let child = try await root.openSessionChannel()
        do {
            try await child.execute(command)
            var output = Data()
            for try await bytes in child.receivedBytes { output.append(bytes) }
            try? await child.close()
            return String(decoding: output, as: UTF8.self)
        } catch {
            try? await child.close()
            throw error
        }
    }
}
