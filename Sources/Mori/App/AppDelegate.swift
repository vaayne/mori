import AppKit
import MoriCore
import MoriPersistence
import MoriTerminal
import MoriTmux

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var mainWindowController: MainWindowController?
    private var workspaceManager: WorkspaceManager?
    private var appState: AppState?
    private var terminalAreaController: TerminalAreaViewController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Task 3.8: Single instance check
        enforceSingleInstance()

        // Initialize core dependencies
        let state = AppState()
        self.appState = state

        let database: AppDatabase
        do {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!.appendingPathComponent("Mori", isDirectory: true)
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            let dbPath = appSupport.appendingPathComponent("mori.sqlite").path
            database = try AppDatabase.onDisk(path: dbPath)
        } catch {
            // Fallback to in-memory if disk DB fails
            database = try! AppDatabase.inMemory()
        }

        let projectRepo = ProjectRepository(database: database)
        let worktreeRepo = WorktreeRepository(database: database)
        let uiStateRepo = UIStateRepository(database: database)
        let tmuxBackend = TmuxBackend()

        let manager = WorkspaceManager(
            appState: state,
            projectRepo: projectRepo,
            worktreeRepo: worktreeRepo,
            uiStateRepo: uiStateRepo,
            tmuxBackend: tmuxBackend
        )
        self.workspaceManager = manager

        // Load persisted state
        try? manager.loadAll()

        // Build the window
        let windowController = MainWindowController()
        self.mainWindowController = windowController

        // Wire "Add Project" toolbar action
        windowController.onAddProject = { [weak self] in
            self?.showAddProjectPanel()
        }

        // Build split view children
        let railController = ProjectRailHostingController(
            appState: state,
            onSelect: { [weak manager] projectId in
                manager?.selectProject(projectId)
            }
        )

        let sidebarController = WorktreeSidebarHostingController(
            appState: state,
            onSelectWorktree: { [weak manager] worktreeId in
                manager?.selectWorktree(worktreeId)
            },
            onSelectWindow: { [weak manager] windowId in
                manager?.selectWindow(windowId)
            }
        )

        let terminalArea = TerminalAreaViewController()
        self.terminalAreaController = terminalArea

        let splitVC = RootSplitViewController(
            railController: railController,
            sidebarController: sidebarController,
            contentController: terminalArea
        )

        windowController.contentViewController = splitVC
        windowController.showWindow(nil)

        // Wire terminal switch: when worktree selection changes, attach terminal
        manager.onTerminalSwitch = { [weak terminalArea] sessionName, workingDirectory in
            terminalArea?.attachToSession(sessionName: sessionName, workingDirectory: workingDirectory)
        }

        // Update window title from current project
        updateWindowTitle()

        // Start tmux polling
        Task {
            await tmuxBackend.setOnChange { [weak manager] _ in
                Task { @MainActor in
                    await manager?.refreshRuntimeState()
                }
            }
            await tmuxBackend.startPolling()

            // Initial runtime state load
            await manager.refreshRuntimeState()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up terminal surfaces
        terminalAreaController?.removeAllSurfaces()
        // TODO: Phase 5 — Persist UI state before exit
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Add Project (Task 3.6)

    private func showAddProjectPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a project folder"
        panel.prompt = "Add Project"

        guard let window = mainWindowController?.window else { return }

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.handleAddProject(path: url.path)
        }
    }

    private func handleAddProject(path: String) {
        guard let manager = workspaceManager else { return }
        do {
            let project = try manager.addProject(path: path)
            mainWindowController?.updateTitle(projectName: project.name)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Failed to add project"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    // MARK: - Helpers

    private func updateWindowTitle() {
        mainWindowController?.updateTitle(projectName: appState?.selectedProject?.name)
    }

    // MARK: - Single Instance (Task 3.8)

    private func enforceSingleInstance() {
        let runningApps = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.mori.app"
        )

        let otherInstances = runningApps.filter { $0 != NSRunningApplication.current }
        if let existing = otherInstances.first {
            existing.activate()
            NSApp.terminate(nil)
        }
    }
}
