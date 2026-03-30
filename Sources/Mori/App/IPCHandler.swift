import Foundation
import MoriCore
import MoriIPC
import MoriTmux

/// Dispatches IPC requests to WorkspaceManager methods.
/// Runs on `@MainActor` because WorkspaceManager and AppState are `@MainActor`.
@MainActor
final class IPCHandler {

    private weak var workspaceManager: WorkspaceManager?

    init(workspaceManager: WorkspaceManager) {
        self.workspaceManager = workspaceManager
    }

    /// Handle an incoming IPC request and return a response.
    /// Called from the IPCServer actor; dispatched to MainActor because
    /// WorkspaceManager and AppState are MainActor-isolated.
    func handle(_ request: IPCRequest) async -> IPCResponse {
        guard let manager = workspaceManager else {
            return .error(message: "WorkspaceManager not available")
        }

        switch request.command {
        case .projectList:
            return handleProjectList(manager: manager)

        case .worktreeCreate(let project, let branch):
            return await handleWorktreeCreate(manager: manager, projectName: project, branch: branch)

        case .focus(let project, let worktree):
            return handleFocus(manager: manager, projectName: project, worktreeName: worktree)

        case .send(let project, let worktree, let window, let keys):
            return await handleSend(manager: manager, projectName: project, worktreeName: worktree, windowName: window, keys: keys)

        case .newWindow(let project, let worktree, let name):
            return await handleNewWindow(manager: manager, projectName: project, worktreeName: worktree, windowName: name)

        case .open(let path):
            return await handleOpen(manager: manager, path: path)

        case .setWorkflowStatus(let project, let worktree, let status):
            return handleSetWorkflowStatus(manager: manager, projectName: project, worktreeName: worktree, statusString: status)

        case .paneList:
            return handlePaneList(manager: manager)

        case .paneRead(let project, let worktree, let window, let lines):
            return await handlePaneRead(manager: manager, projectName: project, worktreeName: worktree, windowName: window, lines: lines)

        case .paneMessage(let project, let worktree, let window, let text,
                         let senderProject, let senderWorktree, let senderWindow, let senderPaneId):
            return await handlePaneMessage(manager: manager, projectName: project, worktreeName: worktree, windowName: window, text: text,
                                           senderProject: senderProject, senderWorktree: senderWorktree,
                                           senderWindow: senderWindow, senderPaneId: senderPaneId)
        }
    }

    // MARK: - Command Handlers

    private func handleProjectList(manager: WorkspaceManager) -> IPCResponse {
        let projects = manager.appState.projects
        let entries = projects.map { ProjectEntry(name: $0.name, path: $0.repoRootPath) }
        do {
            let data = try JSONEncoder().encode(entries)
            return .success(payload: data)
        } catch {
            return .error(message: "Failed to encode projects: \(error.localizedDescription)")
        }
    }

    private func handleWorktreeCreate(manager: WorkspaceManager, projectName: String, branch: String) async -> IPCResponse {
        guard let project = manager.appState.projects.first(where: {
            $0.name.caseInsensitiveCompare(projectName) == .orderedSame
        }) else {
            return .error(message: "Project not found: \(projectName)")
        }

        do {
            let worktree = try await manager.createWorktree(projectId: project.id, branchName: branch)
            let entry = WorktreeEntry(name: worktree.name, branch: worktree.branch ?? "", path: worktree.path)
            let data = try JSONEncoder().encode(entry)
            return .success(payload: data)
        } catch {
            return .error(message: "Failed to create worktree: \(error.localizedDescription)")
        }
    }

    private func handleFocus(manager: WorkspaceManager, projectName: String, worktreeName: String) -> IPCResponse {
        guard let project = manager.appState.projects.first(where: {
            $0.name.caseInsensitiveCompare(projectName) == .orderedSame
        }) else {
            return .error(message: "Project not found: \(projectName)")
        }

        guard let worktree = manager.appState.worktrees.first(where: {
            $0.projectId == project.id && $0.name.caseInsensitiveCompare(worktreeName) == .orderedSame
        }) else {
            return .error(message: "Worktree not found: \(worktreeName)")
        }

        manager.selectProject(project.id)
        manager.selectWorktree(worktree.id)
        return .success(payload: nil)
    }

    private func handleSend(manager: WorkspaceManager, projectName: String, worktreeName: String, windowName: String, keys: String) async -> IPCResponse {
        guard let project = manager.appState.projects.first(where: {
            $0.name.caseInsensitiveCompare(projectName) == .orderedSame
        }) else {
            return .error(message: "Project not found: \(projectName)")
        }

        guard let worktree = manager.appState.worktrees.first(where: {
            $0.projectId == project.id && $0.name.caseInsensitiveCompare(worktreeName) == .orderedSame
        }) else {
            return .error(message: "Worktree not found: \(worktreeName)")
        }

        guard let sessionName = worktree.tmuxSessionName else {
            return .error(message: "Worktree has no tmux session")
        }

        // Find window by name
        guard let runtimeWindow = manager.appState.runtimeWindows.first(where: {
            $0.worktreeId == worktree.id && $0.title.caseInsensitiveCompare(windowName) == .orderedSame
        }) else {
            return .error(message: "Window not found: \(windowName)")
        }

        // Find the active pane in this window (use the window's first pane)
        let paneId = manager.rawTmuxWindowId(from: runtimeWindow)
        let tmux = manager.tmuxBackendForWorktree(worktree)

        do {
            try await tmux.sendKeys(sessionId: sessionName, paneId: paneId, keys: keys)
            return .success(payload: nil)
        } catch {
            return .error(message: "Failed to send keys: \(error.localizedDescription)")
        }
    }

    private func handleNewWindow(manager: WorkspaceManager, projectName: String, worktreeName: String, windowName: String?) async -> IPCResponse {
        guard let project = manager.appState.projects.first(where: {
            $0.name.caseInsensitiveCompare(projectName) == .orderedSame
        }) else {
            return .error(message: "Project not found: \(projectName)")
        }

        guard let worktree = manager.appState.worktrees.first(where: {
            $0.projectId == project.id && $0.name.caseInsensitiveCompare(worktreeName) == .orderedSame
        }) else {
            return .error(message: "Worktree not found: \(worktreeName)")
        }

        guard let sessionName = worktree.tmuxSessionName else {
            return .error(message: "Worktree has no tmux session")
        }

        let tmux = manager.tmuxBackendForWorktree(worktree)
        do {
            _ = try await tmux.createWindow(
                sessionId: sessionName,
                name: windowName,
                cwd: worktree.path
            )
            await manager.refreshRuntimeState()
            return .success(payload: nil)
        } catch {
            return .error(message: "Failed to create window: \(error.localizedDescription)")
        }
    }

    private func handleSetWorkflowStatus(manager: WorkspaceManager, projectName: String, worktreeName: String, statusString: String) -> IPCResponse {
        guard let validStatus = WorkflowStatus(rawValue: statusString) else {
            let validValues = WorkflowStatus.allCases.map(\.rawValue).joined(separator: ", ")
            return .error(message: "Invalid status: \(statusString). Valid values: \(validValues)")
        }

        guard let project = manager.appState.projects.first(where: {
            $0.name.caseInsensitiveCompare(projectName) == .orderedSame
        }) else {
            return .error(message: "Project not found: \(projectName)")
        }

        guard let worktree = manager.appState.worktrees.first(where: {
            $0.projectId == project.id && $0.name.caseInsensitiveCompare(worktreeName) == .orderedSame
        }) else {
            return .error(message: "Worktree not found: \(worktreeName)")
        }

        manager.setWorkflowStatus(worktreeId: worktree.id, status: validStatus)
        return .success(payload: nil)
    }

    // TODO: Enumerate individual panes for multi-pane windows.
    // Currently emits one AgentPaneInfo per window (using activePaneId),
    // so non-active panes in multi-pane windows are invisible to agents.
    // Requires expanding RuntimeWindow to carry all pane IDs from the refresh cycle.
    private func handlePaneList(manager: WorkspaceManager) -> IPCResponse {
        var entries: [AgentPaneInfo] = []
        for project in manager.appState.projects {
            let worktrees = manager.appState.worktrees.filter { $0.projectId == project.id }
            for worktree in worktrees {
                let windows = manager.appState.runtimeWindows.filter { $0.worktreeId == worktree.id }
                for window in windows {
                    let paneId = window.activePaneId ?? manager.rawTmuxWindowId(from: window)
                    let entry = AgentPaneInfo(
                        endpoint: worktree.resolvedLocation.endpointKey,
                        tmuxPaneId: paneId,
                        projectName: project.name,
                        worktreeName: worktree.name,
                        windowName: window.title,
                        agentState: window.agentState,
                        detectedAgent: window.detectedAgent
                    )
                    entries.append(entry)
                }
            }
        }
        do {
            let data = try JSONEncoder().encode(entries)
            return .success(payload: data)
        } catch {
            return .error(message: "Failed to encode pane list: \(error.localizedDescription)")
        }
    }

    private func handlePaneRead(manager: WorkspaceManager, projectName: String, worktreeName: String, windowName: String, lines: Int) async -> IPCResponse {
        guard let (worktree, runtimeWindow) = resolveWindow(manager: manager, projectName: projectName, worktreeName: worktreeName, windowName: windowName) else {
            return .error(message: "Window not found: \(projectName)/\(worktreeName)/\(windowName)")
        }

        let paneId = runtimeWindow.activePaneId ?? manager.rawTmuxWindowId(from: runtimeWindow)
        let tmux = manager.tmuxBackendForWorktree(worktree)
        let clampedLines = min(max(lines, 1), 200)

        do {
            let output = try await tmux.capturePaneOutput(paneId: paneId, lineCount: clampedLines)
            let data = Data(output.utf8)
            return .success(payload: data)
        } catch {
            return .error(message: "Failed to capture pane output: \(error.localizedDescription)")
        }
    }

    private func handlePaneMessage(manager: WorkspaceManager, projectName: String, worktreeName: String, windowName: String, text: String,
                                     senderProject: String?, senderWorktree: String?, senderWindow: String?, senderPaneId: String?) async -> IPCResponse {
        guard let (worktree, runtimeWindow) = resolveWindow(manager: manager, projectName: projectName, worktreeName: worktreeName, windowName: windowName) else {
            return .error(message: "Window not found: \(projectName)/\(worktreeName)/\(windowName)")
        }

        guard let sessionName = worktree.tmuxSessionName else {
            return .error(message: "Worktree has no tmux session")
        }

        let paneId = runtimeWindow.activePaneId ?? manager.rawTmuxWindowId(from: runtimeWindow)
        let tmux = manager.tmuxBackendForWorktree(worktree)

        // Use sender identity transmitted from the CLI caller via IPC
        let message = AgentMessage(
            fromProject: senderProject ?? "cli",
            fromWorktree: senderWorktree ?? "cli",
            fromWindow: senderWindow ?? "cli",
            fromPaneId: senderPaneId ?? "unknown",
            text: text
        )

        do {
            // sendKeys already appends Enter — no need for a second call
            try await tmux.sendKeys(sessionId: sessionName, paneId: paneId, keys: message.envelope)
            return .success(payload: nil)
        } catch {
            return .error(message: "Failed to send message: \(error.localizedDescription)")
        }
    }

    /// Resolve project/worktree/window triplet to a (Worktree, RuntimeWindow) pair.
    private func resolveWindow(manager: WorkspaceManager, projectName: String, worktreeName: String, windowName: String) -> (Worktree, RuntimeWindow)? {
        guard let project = manager.appState.projects.first(where: {
            $0.name.caseInsensitiveCompare(projectName) == .orderedSame
        }) else { return nil }

        guard let worktree = manager.appState.worktrees.first(where: {
            $0.projectId == project.id && $0.name.caseInsensitiveCompare(worktreeName) == .orderedSame
        }) else { return nil }

        guard let runtimeWindow = manager.appState.runtimeWindows.first(where: {
            $0.worktreeId == worktree.id && $0.title.caseInsensitiveCompare(windowName) == .orderedSame
        }) else { return nil }

        return (worktree, runtimeWindow)
    }

    private func handleOpen(manager: WorkspaceManager, path: String) async -> IPCResponse {
        do {
            let project = try await manager.addProject(path: path)
            let entry = ProjectEntry(name: project.name, path: project.repoRootPath)
            let data = try JSONEncoder().encode(entry)
            return .success(payload: data)
        } catch {
            return .error(message: "Failed to open project: \(error.localizedDescription)")
        }
    }
}

// MARK: - JSON Response Models

private struct ProjectEntry: Codable, Sendable {
    let name: String
    let path: String
}

private struct WorktreeEntry: Codable, Sendable {
    let name: String
    let branch: String
    let path: String
}
