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

        // MARK: Project
        case .projectList:
            return handleProjectList(manager: manager)

        case .open(let path):
            return await handleOpen(manager: manager, path: path)

        // MARK: Worktree
        case .worktreeList(let project):
            return handleWorktreeList(manager: manager, projectName: project)

        case .worktreeCreate(let project, let branch):
            return await handleWorktreeCreate(manager: manager, projectName: project, branch: branch)

        case .worktreeDelete(let project, let worktree):
            return await handleWorktreeDelete(manager: manager, projectName: project, worktreeName: worktree)

        // MARK: Window
        case .windowList(let project, let worktree):
            return handleWindowList(manager: manager, projectName: project, worktreeName: worktree)

        case .windowNew(let project, let worktree, let name):
            return await handleWindowNew(manager: manager, projectName: project, worktreeName: worktree, windowName: name)

        case .windowRename(let project, let worktree, let window, let newName):
            return await handleWindowRename(manager: manager, projectName: project, worktreeName: worktree, windowName: window, newName: newName)

        case .windowClose(let project, let worktree, let window):
            return await handleWindowClose(manager: manager, projectName: project, worktreeName: worktree, windowName: window)

        // MARK: Pane
        case .paneList(let project, let worktree, let window):
            return handlePaneList(manager: manager, projectFilter: project, worktreeFilter: worktree, windowFilter: window)

        case .paneNew(let project, let worktree, let window, let split, let name):
            return await handlePaneNew(manager: manager, projectName: project, worktreeName: worktree, windowName: window, split: split, name: name)

        case .paneSend(let project, let worktree, let window, let pane, let keys):
            return await handlePaneSend(manager: manager, projectName: project, worktreeName: worktree, windowName: window, paneId: pane, keys: keys)

        case .paneRead(let project, let worktree, let window, let pane, let lines):
            return await handlePaneRead(manager: manager, projectName: project, worktreeName: worktree, windowName: window, paneId: pane, lines: lines)

        case .paneRename(let project, let worktree, let window, let pane, let newName):
            return await handlePaneRename(manager: manager, projectName: project, worktreeName: worktree, windowName: window, paneId: pane, newName: newName)

        case .paneClose(let project, let worktree, let window, let pane):
            return await handlePaneClose(manager: manager, projectName: project, worktreeName: worktree, windowName: window, paneId: pane)

        case .paneMessage(let project, let worktree, let window, let text,
                         let senderProject, let senderWorktree, let senderWindow, let senderPaneId):
            return await handlePaneMessage(manager: manager, projectName: project, worktreeName: worktree, windowName: window, text: text,
                                           senderProject: senderProject, senderWorktree: senderWorktree,
                                           senderWindow: senderWindow, senderPaneId: senderPaneId)

        // MARK: Focus
        case .focusProject(let project):
            return handleFocusProject(manager: manager, projectName: project)

        case .focus(let project, let worktree):
            return handleFocus(manager: manager, projectName: project, worktreeName: worktree)

        case .focusWindow(let project, let worktree, let window):
            return handleFocusWindow(manager: manager, projectName: project, worktreeName: worktree, windowName: window)
        }
    }

    // MARK: - Project Handlers

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

    // MARK: - Worktree Handlers

    private func handleWorktreeList(manager: WorkspaceManager, projectName: String) -> IPCResponse {
        guard let project = manager.appState.projects.first(where: {
            $0.name.caseInsensitiveCompare(projectName) == .orderedSame
        }) else {
            return .error(message: "Project not found: \(projectName)")
        }

        let worktrees = manager.appState.worktrees.filter { $0.projectId == project.id }
        let entries = worktrees.map { WorktreeEntry(name: $0.name, branch: $0.branch ?? "", path: $0.path) }
        do {
            let data = try JSONEncoder().encode(entries)
            return .success(payload: data)
        } catch {
            return .error(message: "Failed to encode worktrees: \(error.localizedDescription)")
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

    private func handleWorktreeDelete(manager: WorkspaceManager, projectName: String, worktreeName: String) async -> IPCResponse {
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

        do {
            try await manager.deleteWorktree(worktreeId: worktree.id)
            return .success(payload: nil)
        } catch {
            return .error(message: "Failed to delete worktree: \(error.localizedDescription)")
        }
    }

    // MARK: - Window Handlers

    private func handleWindowList(manager: WorkspaceManager, projectName: String, worktreeName: String) -> IPCResponse {
        guard let (_, worktree) = resolveWorktree(manager: manager, projectName: projectName, worktreeName: worktreeName) else {
            return .error(message: "Worktree not found: \(projectName)/\(worktreeName)")
        }

        let windows = manager.appState.runtimeWindows.filter { $0.worktreeId == worktree.id }
        let entries = windows.map { rw in
            WindowEntry(
                name: rw.title,
                windowId: rw.tmuxWindowId,
                paneCount: rw.paneCount
            )
        }
        do {
            let data = try JSONEncoder().encode(entries)
            return .success(payload: data)
        } catch {
            return .error(message: "Failed to encode windows: \(error.localizedDescription)")
        }
    }

    private func handleWindowNew(manager: WorkspaceManager, projectName: String, worktreeName: String, windowName: String?) async -> IPCResponse {
        guard let (_, worktree) = resolveWorktree(manager: manager, projectName: projectName, worktreeName: worktreeName) else {
            return .error(message: "Worktree not found: \(projectName)/\(worktreeName)")
        }

        guard let sessionName = worktree.tmuxSessionName else {
            return .error(message: "Worktree has no tmux session")
        }

        let tmux = manager.tmuxBackendForWorktree(worktree)
        do {
            let window = try await tmux.createWindow(sessionId: sessionName, name: windowName, cwd: worktree.path)
            await manager.refreshRuntimeState()
            let entry = WindowEntry(name: window.name, windowId: window.windowId, paneCount: window.panes.count)
            let data = try JSONEncoder().encode(entry)
            return .success(payload: data)
        } catch {
            return .error(message: "Failed to create window: \(error.localizedDescription)")
        }
    }

    private func handleWindowRename(manager: WorkspaceManager, projectName: String, worktreeName: String, windowName: String, newName: String) async -> IPCResponse {
        guard let (_, worktree, runtimeWindow) = resolveWindow(manager: manager, projectName: projectName, worktreeName: worktreeName, windowName: windowName) else {
            return .error(message: "Window not found: \(projectName)/\(worktreeName)/\(windowName)")
        }

        guard let sessionName = worktree.tmuxSessionName else {
            return .error(message: "Worktree has no tmux session")
        }

        let rawWindowId = manager.rawTmuxWindowId(from: runtimeWindow)
        let tmux = manager.tmuxBackendForWorktree(worktree)

        do {
            try await tmux.renameWindow(sessionId: sessionName, windowId: rawWindowId, newName: newName)
            await manager.refreshRuntimeState()
            return .success(payload: nil)
        } catch {
            return .error(message: "Failed to rename window: \(error.localizedDescription)")
        }
    }

    private func handleWindowClose(manager: WorkspaceManager, projectName: String, worktreeName: String, windowName: String) async -> IPCResponse {
        guard let (_, worktree, runtimeWindow) = resolveWindow(manager: manager, projectName: projectName, worktreeName: worktreeName, windowName: windowName) else {
            return .error(message: "Window not found: \(projectName)/\(worktreeName)/\(windowName)")
        }

        guard let sessionName = worktree.tmuxSessionName else {
            return .error(message: "Worktree has no tmux session")
        }

        let rawWindowId = manager.rawTmuxWindowId(from: runtimeWindow)
        let tmux = manager.tmuxBackendForWorktree(worktree)

        do {
            try await tmux.killWindow(sessionId: sessionName, windowId: rawWindowId)
            await manager.refreshRuntimeState()
            return .success(payload: nil)
        } catch {
            return .error(message: "Failed to close window: \(error.localizedDescription)")
        }
    }

    // MARK: - Pane Handlers

    private func handlePaneList(manager: WorkspaceManager, projectFilter: String?, worktreeFilter: String?, windowFilter: String?) -> IPCResponse {
        var entries: [AgentPaneInfo] = []
        for project in manager.appState.projects {
            if let projectFilter,
               project.name.caseInsensitiveCompare(projectFilter) != .orderedSame {
                continue
            }
            let worktrees = manager.appState.worktrees.filter { $0.projectId == project.id }
            for worktree in worktrees {
                if let worktreeFilter,
                   worktree.name.caseInsensitiveCompare(worktreeFilter) != .orderedSame {
                    continue
                }
                let windows = manager.appState.runtimeWindows.filter { $0.worktreeId == worktree.id }
                for window in windows {
                    if let windowFilter,
                       window.title.caseInsensitiveCompare(windowFilter) != .orderedSame {
                        continue
                    }
                    let endpointKey = worktree.resolvedLocation.endpointKey
                    let sessions = manager.sessionsForWorktree(worktree)
                    let rawWindowId = manager.rawTmuxWindowId(from: window)

                    if let (_, tmuxWindow) = sessions
                        .compactMap({ session in
                            session.windows.first(where: { $0.windowId == rawWindowId }).map { (session, $0) }
                        })
                        .first,
                       !tmuxWindow.panes.isEmpty {
                        for pane in tmuxWindow.panes {
                            let entry = AgentPaneInfo(
                                endpoint: endpointKey,
                                tmuxPaneId: pane.paneId,
                                projectName: project.name,
                                worktreeName: worktree.name,
                                windowName: window.title,
                                paneTitle: pane.title,
                                agentState: agentState(for: pane, fallback: window.agentState),
                                detectedAgent: pane.agentName ?? window.detectedAgent
                            )
                            entries.append(entry)
                        }
                    } else {
                        let paneId = window.activePaneId ?? rawWindowId
                        let entry = AgentPaneInfo(
                            endpoint: endpointKey,
                            tmuxPaneId: paneId,
                            projectName: project.name,
                            worktreeName: worktree.name,
                            windowName: window.title,
                            paneTitle: nil,
                            agentState: window.agentState,
                            detectedAgent: window.detectedAgent
                        )
                        entries.append(entry)
                    }
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

    private func handlePaneNew(manager: WorkspaceManager, projectName: String, worktreeName: String, windowName: String, split: String?, name: String?) async -> IPCResponse {
        guard let (_, worktree, runtimeWindow) = resolveWindow(manager: manager, projectName: projectName, worktreeName: worktreeName, windowName: windowName) else {
            return .error(message: "Window not found: \(projectName)/\(worktreeName)/\(windowName)")
        }

        guard let sessionName = worktree.tmuxSessionName else {
            return .error(message: "Worktree has no tmux session")
        }

        // Resolve pane target: use active pane ID if available, otherwise fall back to session
        let activePaneId = runtimeWindow.activePaneId ?? manager.rawTmuxWindowId(from: runtimeWindow)
        let horizontal = split != "v"
        let tmux = manager.tmuxBackendForWorktree(worktree)

        do {
            let pane = try await tmux.splitPane(sessionId: sessionName, paneId: activePaneId, horizontal: horizontal, cwd: worktree.path)
            if let name {
                try? await tmux.renamePane(paneId: pane.paneId, newName: name)
            }
            await manager.refreshRuntimeState()
            let entry = PaneNewEntry(paneId: pane.paneId, window: windowName)
            let data = try JSONEncoder().encode(entry)
            return .success(payload: data)
        } catch {
            return .error(message: "Failed to create pane: \(error.localizedDescription)")
        }
    }

    private func handlePaneSend(manager: WorkspaceManager, projectName: String, worktreeName: String, windowName: String, paneId: String?, keys: String) async -> IPCResponse {
        guard let (_, worktree, runtimeWindow) = resolveWindow(manager: manager, projectName: projectName, worktreeName: worktreeName, windowName: windowName) else {
            return .error(message: "Window not found: \(projectName)/\(worktreeName)/\(windowName)")
        }

        guard let sessionName = worktree.tmuxSessionName else {
            return .error(message: "Worktree has no tmux session")
        }

        let targetPaneId = paneId ?? runtimeWindow.activePaneId ?? manager.rawTmuxWindowId(from: runtimeWindow)
        let tmux = manager.tmuxBackendForWorktree(worktree)

        do {
            try await tmux.sendKeys(sessionId: sessionName, paneId: targetPaneId, keys: keys)
            return .success(payload: nil)
        } catch {
            return .error(message: "Failed to send keys: \(error.localizedDescription)")
        }
    }

    private func handlePaneRead(manager: WorkspaceManager, projectName: String, worktreeName: String, windowName: String, paneId: String?, lines: Int) async -> IPCResponse {
        guard let (_, worktree, runtimeWindow) = resolveWindow(manager: manager, projectName: projectName, worktreeName: worktreeName, windowName: windowName) else {
            return .error(message: "Window not found: \(projectName)/\(worktreeName)/\(windowName)")
        }

        let targetPaneId = paneId ?? runtimeWindow.activePaneId ?? manager.rawTmuxWindowId(from: runtimeWindow)
        let tmux = manager.tmuxBackendForWorktree(worktree)
        let clampedLines = min(max(lines, 1), 200)

        do {
            let output = try await tmux.capturePaneOutput(paneId: targetPaneId, lineCount: clampedLines)
            let data = Data(output.utf8)
            return .success(payload: data)
        } catch {
            return .error(message: "Failed to capture pane output: \(error.localizedDescription)")
        }
    }

    private func handlePaneRename(manager: WorkspaceManager, projectName: String, worktreeName: String, windowName: String, paneId: String, newName: String) async -> IPCResponse {
        guard let (_, worktree, _) = resolveWindow(manager: manager, projectName: projectName, worktreeName: worktreeName, windowName: windowName) else {
            return .error(message: "Window not found: \(projectName)/\(worktreeName)/\(windowName)")
        }

        let tmux = manager.tmuxBackendForWorktree(worktree)

        do {
            try await tmux.renamePane(paneId: paneId, newName: newName)
            return .success(payload: nil)
        } catch {
            return .error(message: "Failed to rename pane: \(error.localizedDescription)")
        }
    }

    private func handlePaneClose(manager: WorkspaceManager, projectName: String, worktreeName: String, windowName: String, paneId: String?) async -> IPCResponse {
        guard let (_, worktree, runtimeWindow) = resolveWindow(manager: manager, projectName: projectName, worktreeName: worktreeName, windowName: windowName) else {
            return .error(message: "Window not found: \(projectName)/\(worktreeName)/\(windowName)")
        }

        guard let sessionName = worktree.tmuxSessionName else {
            return .error(message: "Worktree has no tmux session")
        }

        let targetPaneId = paneId ?? runtimeWindow.activePaneId ?? manager.rawTmuxWindowId(from: runtimeWindow)
        let tmux = manager.tmuxBackendForWorktree(worktree)

        do {
            try await tmux.killPane(sessionId: sessionName, paneId: targetPaneId)
            await manager.refreshRuntimeState()
            return .success(payload: nil)
        } catch {
            return .error(message: "Failed to close pane: \(error.localizedDescription)")
        }
    }

    private func handlePaneMessage(manager: WorkspaceManager, projectName: String, worktreeName: String, windowName: String, text: String,
                                     senderProject: String?, senderWorktree: String?, senderWindow: String?, senderPaneId: String?) async -> IPCResponse {
        guard let (_, worktree, runtimeWindow) = resolveWindow(manager: manager, projectName: projectName, worktreeName: worktreeName, windowName: windowName) else {
            return .error(message: "Window not found: \(projectName)/\(worktreeName)/\(windowName)")
        }

        guard let sessionName = worktree.tmuxSessionName else {
            return .error(message: "Worktree has no tmux session")
        }

        let paneId = runtimeWindow.activePaneId ?? manager.rawTmuxWindowId(from: runtimeWindow)
        let tmux = manager.tmuxBackendForWorktree(worktree)

        let message = AgentMessage(
            fromProject: senderProject ?? "cli",
            fromWorktree: senderWorktree ?? "cli",
            fromWindow: senderWindow ?? "cli",
            fromPaneId: senderPaneId ?? "unknown",
            text: text
        )

        do {
            try await tmux.sendKeys(sessionId: sessionName, paneId: paneId, keys: message.envelope)
            return .success(payload: nil)
        } catch {
            return .error(message: "Failed to send message: \(error.localizedDescription)")
        }
    }

    // MARK: - Focus Handlers

    private func handleFocusProject(manager: WorkspaceManager, projectName: String) -> IPCResponse {
        guard let project = manager.appState.projects.first(where: {
            $0.name.caseInsensitiveCompare(projectName) == .orderedSame
        }) else {
            return .error(message: "Project not found: \(projectName)")
        }
        manager.selectProject(project.id)
        return .success(payload: nil)
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

    private func handleFocusWindow(manager: WorkspaceManager, projectName: String, worktreeName: String, windowName: String) -> IPCResponse {
        guard let (_, worktree, runtimeWindow) = resolveWindow(manager: manager, projectName: projectName, worktreeName: worktreeName, windowName: windowName) else {
            return .error(message: "Window not found: \(projectName)/\(worktreeName)/\(windowName)")
        }

        guard let project = manager.appState.projects.first(where: { $0.id == worktree.projectId }) else {
            return .error(message: "Project not found for worktree")
        }

        manager.selectProject(project.id)
        manager.selectWorktree(worktree.id)
        manager.selectWindow(runtimeWindow.tmuxWindowId)
        return .success(payload: nil)
    }

    // MARK: - Resolution Helpers

    private func agentState(for pane: TmuxPane, fallback: AgentState) -> AgentState {
        guard let hookState = pane.agentState?.lowercased() else {
            return fallback
        }
        switch hookState {
        case "working": return .running
        case "waiting": return .waitingForInput
        case "done": return .completed
        case "error": return .error
        default: return fallback
        }
    }

    private func resolveWorktree(manager: WorkspaceManager, projectName: String, worktreeName: String) -> (Project, Worktree)? {
        guard let project = manager.appState.projects.first(where: {
            $0.name.caseInsensitiveCompare(projectName) == .orderedSame
        }) else { return nil }

        guard let worktree = manager.appState.worktrees.first(where: {
            $0.projectId == project.id && $0.name.caseInsensitiveCompare(worktreeName) == .orderedSame
        }) else { return nil }

        return (project, worktree)
    }

    private func resolveWindow(manager: WorkspaceManager, projectName: String, worktreeName: String, windowName: String) -> (Project, Worktree, RuntimeWindow)? {
        guard let (project, worktree) = resolveWorktree(manager: manager, projectName: projectName, worktreeName: worktreeName) else { return nil }

        guard let runtimeWindow = manager.appState.runtimeWindows.first(where: {
            $0.worktreeId == worktree.id && $0.title.caseInsensitiveCompare(windowName) == .orderedSame
        }) else { return nil }

        return (project, worktree, runtimeWindow)
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

private struct WindowEntry: Codable, Sendable {
    let name: String
    let windowId: String
    let paneCount: Int
}

private struct PaneNewEntry: Codable, Sendable {
    let paneId: String
    let window: String
}
