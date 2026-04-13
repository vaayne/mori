import Foundation
import MoriCore

enum MoriRemoteTransferExportError: LocalizedError {
    case notRemoteProject

    var errorDescription: String? {
        switch self {
        case .notRemoteProject:
            return String.localized("This project is not an SSH remote project.")
        }
    }
}

@MainActor
enum MoriRemoteTransferExport {
    /// Builds a QR payload for MoriRemote from the given remote project and current sidebar selection.
    static func makePayload(
        appState: AppState,
        projectId: UUID,
        includePassword: Bool
    ) throws -> MoriRemoteTransferPayload {
        guard let project = appState.projects.first(where: { $0.id == projectId }),
              case .ssh(let ssh) = project.resolvedLocation
        else {
            throw MoriRemoteTransferExportError.notRemoteProject
        }

        let defaultSession = resolveDefaultSession(appState: appState, projectId: projectId)
        let username: String
        if let u = ssh.user?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
            username = u
        } else {
            username = NSUserName()
        }

        var password: String?
        if includePassword {
            // Always try Keychain when the user opts in — older projects may omit `authMethod` and decode as `.publicKey`.
            password = try passwordFromKeychain(for: ssh)
        }

        return MoriRemoteTransferPayload(
            name: project.name,
            host: ssh.host,
            port: ssh.port ?? 22,
            username: username,
            password: password,
            defaultSession: defaultSession
        )
    }

    /// Keychain entries use `SSHWorkspaceLocation.endpointKey`. Try user/port combinations that differ between
    /// connect-time saves (wizard) and persisted project data (nil user, implicit macOS user, port omitted vs 22).
    private static func passwordFromKeychain(for ssh: SSHWorkspaceLocation) throws -> String? {
        let host = ssh.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = ssh.user?.trimmingCharacters(in: .whitespacesAndNewlines)
        let osUser = NSUserName()

        let usersToTry: [String?]
        if let tu = trimmedUser, !tu.isEmpty {
            var users: [String?] = [tu, nil]
            if tu != osUser { users.append(osUser) }
            usersToTry = users
        } else {
            usersToTry = [nil, osUser]
        }

        let portsToTry: [Int?]
        switch ssh.port {
        case nil:
            portsToTry = [nil, 22]
        case .some(22):
            portsToTry = [22, nil]
        case .some(let p):
            portsToTry = [p]
        }

        var seenKeys = Set<String>()
        for u in usersToTry {
            for p in portsToTry {
                let loc = SSHWorkspaceLocation(host: host, user: u, port: p, authMethod: ssh.authMethod)
                let key = loc.endpointKey
                guard seenKeys.insert(key).inserted else { continue }
                if let pw = try SSHCredentialStore.password(for: loc) { return pw }
            }
        }
        return nil
    }

    private static func resolveDefaultSession(appState: AppState, projectId: UUID) -> String {
        if let wid = appState.uiState.selectedWorktreeId,
           let wt = appState.worktrees.first(where: { $0.id == wid && $0.projectId == projectId }),
           let name = wt.tmuxSessionName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        if let main = appState.worktrees.first(where: { $0.projectId == projectId && $0.isMainWorktree }),
           let name = main.tmuxSessionName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        if let any = appState.worktrees.first(where: { $0.projectId == projectId }),
           let name = any.tmuxSessionName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        return "main"
    }
}
