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

        // Restore previously saved UI state (project, worktree, window selection)
        manager.restoreState()

        // Set up the main menu bar
        setupMainMenu()

        // Update window title from current project
        updateWindowTitle()

        // Check tmux availability and start polling
        Task {
            let tmuxAvailable = await manager.checkTmuxAvailability()
            if !tmuxAvailable {
                showTmuxMissingAlert()
                return
            }

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
        // Persist UI state before exit
        workspaceManager?.saveUIStateOnTerminate()

        // Clean up terminal surfaces
        terminalAreaController?.removeAllSurfaces()
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

    // MARK: - Main Menu (Task 5.4)

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Mori", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Mori", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthersItem = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Mori", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let openProjectItem = NSMenuItem(title: "Open Project...", action: #selector(openProjectMenuAction), keyEquivalent: "o")
        openProjectItem.keyEquivalentModifierMask = [.command, .shift]
        openProjectItem.target = self
        fileMenu.addItem(openProjectItem)
        fileMenu.addItem(.separator())
        let closeItem = NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenu.addItem(closeItem)
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu — copy/paste/select all pass through responder chain to terminal
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
            .keyEquivalentModifierMask = [.command, .control]
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func openProjectMenuAction() {
        showAddProjectPanel()
    }

    // MARK: - Tmux Missing Alert (Task 5.3)

    private func showTmuxMissingAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "tmux not found"
        alert.informativeText = """
            Mori requires tmux to manage terminal sessions. \
            Please install tmux and relaunch the app.

            Install via Homebrew:
              brew install tmux

            Or via MacPorts:
              sudo port install tmux
            """
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
