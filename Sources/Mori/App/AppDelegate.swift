import AppKit
import MoriCore
import MoriGit
import MoriIPC
import MoriPersistence
import MoriTerminal
import MoriTmux
import MoriUI
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    private var mainWindowController: MainWindowController?
    private var workspaceManager: WorkspaceManager?
    private var appState: AppState?
    private var terminalAreaController: TerminalAreaViewController?
    private var commandPaletteController: CommandPaletteController?
    private var rootSplitVC: RootSplitViewController?
    private var keyMonitor: Any?
    private var settingsWindowController: NSWindowController?
    private var sidebarController: SidebarHostingController?
    private var terminalSettings = TerminalSettings.load()
    private var ipcServer: IPCServer?
    private var ipcHandler: IPCHandler?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Task 3.8: Single instance check
        enforceSingleInstance()

        // Set self as notification center delegate for click handling.
        // UNUserNotificationCenter requires a valid bundle proxy — guard for swift run.
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }

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
        let gitBackend = GitBackend()

        let manager = WorkspaceManager(
            appState: state,
            projectRepo: projectRepo,
            worktreeRepo: worktreeRepo,
            uiStateRepo: uiStateRepo,
            tmuxBackend: tmuxBackend,
            gitBackend: gitBackend
        )
        self.workspaceManager = manager

        // Load persisted state
        try? manager.loadAll()

        // Build the window
        let windowController = MainWindowController()
        self.mainWindowController = windowController

        // Build split view children
        let sidebarController = SidebarHostingController(
            appState: state,
            onSelectProject: { [weak manager, weak self] projectId in
                manager?.selectProject(projectId)
                self?.updateWindowTitle()
            },
            onSelectWorktree: { [weak manager, weak self] worktreeId in
                manager?.selectWorktree(worktreeId)
                self?.updateWindowTitle()
            },
            onSelectWindow: { [weak manager, weak self] windowId in
                manager?.selectWindow(windowId)
                self?.updateWindowTitle()
            },
            onCreateWorktree: { [weak manager] branchName in
                guard let manager else { return }
                Task { @MainActor in
                    await manager.handleCreateWorktree(branchName: branchName)
                }
            },
            onRemoveWorktree: { [weak manager] worktreeId in
                guard let manager else { return }
                Task { @MainActor in
                    await manager.removeWorktree(worktreeId: worktreeId)
                }
            },
            onToggleCollapse: { [weak manager] projectId in
                manager?.toggleProjectCollapse(projectId)
            },
            onAddProject: { [weak self] in
                self?.showAddProjectPanel()
            },
            onOpenSettings: { [weak self] in
                self?.showSettingsWindow()
            },
            onOpenCommandPalette: { [weak self] in
                self?.commandPaletteController?.toggle()
            }
        )

        self.sidebarController = sidebarController
        sidebarController.updateAppearance(settings: self.terminalSettings)

        let terminalArea = TerminalAreaViewController()
        self.terminalAreaController = terminalArea

        let splitVC = RootSplitViewController(
            sidebarController: sidebarController,
            contentController: terminalArea
        )
        self.rootSplitVC = splitVC

        windowController.onToggleSidebar = { [weak splitVC] in
            splitVC?.toggleSidebar()
        }

        windowController.contentViewController = splitVC
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Wire terminal switch: when worktree selection changes, attach terminal
        manager.onTerminalSwitch = { [weak terminalArea] sessionName, workingDirectory in
            terminalArea?.attachToSession(sessionName: sessionName, workingDirectory: workingDirectory)
        }

        // Restore previously saved UI state (project, worktree, window selection)
        manager.restoreState()

        // Set up the main menu bar
        setupMainMenu()

        // Set up command palette (Cmd+K)
        setupCommandPalette(appState: state, manager: manager)

        // Start IPC server for ws CLI communication
        startIPCServer(manager: manager)

        // Update window title from current project
        updateWindowTitle()

        // Check tmux availability and start coordinated polling
        Task {
            let tmuxAvailable = await manager.checkTmuxAvailability()
            if !tmuxAvailable {
                showTmuxMissingAlert()
                return
            }

            // Initial runtime state load
            await manager.refreshRuntimeState()

            // Start coordinated polling (tmux + git status on each 5s tick)
            manager.startPolling()

            // Apply terminal theme to tmux sessions
            await TmuxThemeApplicator.apply(settings: self.terminalSettings, tmuxBackend: manager.tmuxBackend)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Remove Cmd+K key monitor
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }

        // Stop IPC server
        if let server = ipcServer {
            Task { await server.stop() }
        }

        // Stop coordinated polling
        workspaceManager?.stopPolling()

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
        Task { @MainActor in
            do {
                let project = try await manager.addProject(path: path)
                mainWindowController?.updateTitle(projectName: project.name)
            } catch {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Failed to add project"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
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
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettingsMenuAction), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
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
        let closeItem = NSMenuItem(title: "Close Tab", action: #selector(closeWindowMenuAction), keyEquivalent: "w")
        closeItem.target = self
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
        let toggleSidebarItem = NSMenuItem(title: "Toggle Sidebar", action: #selector(toggleSidebarMenuAction), keyEquivalent: "0")
        toggleSidebarItem.target = self
        viewMenu.addItem(toggleSidebarItem)
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
            .keyEquivalentModifierMask = [.command, .control]
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Session menu
        let sessionMenuItem = NSMenuItem()
        let sessionMenu = NSMenu(title: "Session")

        let newWindowItem = NSMenuItem(title: "New Window", action: #selector(newWindowMenuAction), keyEquivalent: "t")
        newWindowItem.target = self
        sessionMenu.addItem(newWindowItem)

        sessionMenu.addItem(.separator())

        let splitHItem = NSMenuItem(title: "Split Pane Right", action: #selector(splitHorizontalMenuAction), keyEquivalent: "d")
        splitHItem.target = self
        sessionMenu.addItem(splitHItem)

        let splitVItem = NSMenuItem(title: "Split Pane Down", action: #selector(splitVerticalMenuAction), keyEquivalent: "d")
        splitVItem.keyEquivalentModifierMask = [.command, .shift]
        splitVItem.target = self
        sessionMenu.addItem(splitVItem)

        sessionMenu.addItem(.separator())

        let nextWindowItem = NSMenuItem(title: "Next Window", action: #selector(nextWindowMenuAction), keyEquivalent: "]")
        nextWindowItem.keyEquivalentModifierMask = [.command, .shift]
        nextWindowItem.target = self
        sessionMenu.addItem(nextWindowItem)

        let prevWindowItem = NSMenuItem(title: "Previous Window", action: #selector(previousWindowMenuAction), keyEquivalent: "[")
        prevWindowItem.keyEquivalentModifierMask = [.command, .shift]
        prevWindowItem.target = self
        sessionMenu.addItem(prevWindowItem)

        sessionMenuItem.submenu = sessionMenu
        mainMenu.addItem(sessionMenuItem)

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

    @objc private func toggleSidebarMenuAction() {
        rootSplitVC?.toggleSidebar()
    }

    @objc private func newWindowMenuAction() {
        guard let manager = workspaceManager else { return }
        Task { @MainActor in await manager.createNewWindow() }
    }

    @objc private func closeWindowMenuAction() {
        guard let manager = workspaceManager else { return }
        Task { @MainActor in await manager.closeCurrentWindow() }
    }

    @objc private func splitHorizontalMenuAction() {
        guard let manager = workspaceManager else { return }
        Task { @MainActor in await manager.splitCurrentPane(horizontal: true) }
    }

    @objc private func splitVerticalMenuAction() {
        guard let manager = workspaceManager else { return }
        Task { @MainActor in await manager.splitCurrentPane(horizontal: false) }
    }

    @objc private func nextWindowMenuAction() {
        workspaceManager?.nextWindow()
    }

    @objc private func previousWindowMenuAction() {
        workspaceManager?.previousWindow()
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

    // MARK: - Command Palette (Task 2.6.5)

    private func setupCommandPalette(appState: AppState, manager: WorkspaceManager) {
        let palette = CommandPaletteController(appState: appState)
        self.commandPaletteController = palette

        // Wire item selection to WorkspaceManager navigation and actions
        palette.onSelectItem = { [weak self, weak manager] item in
            guard let self, let manager else { return }
            self.handlePaletteSelection(item, manager: manager)
        }

        // Register Cmd+K and Cmd+1–9 local key monitor
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak palette, weak self] event in
            guard event.modifierFlags.contains(.command) else { return event }
            let key = event.charactersIgnoringModifiers ?? ""

            if key == "k" {
                palette?.toggle()
                return nil
            }

            // Cmd+1 through Cmd+9: select visible worktree by index
            if let digit = Int(key), digit >= 1, digit <= 9 {
                self?.selectWorktreeByShortcut(index: digit)
                return nil
            }

            return event
        }
    }

    private func handlePaletteSelection(_ item: CommandPaletteItem, manager: WorkspaceManager) {
        switch item {
        case .project(let id, _):
            manager.selectProject(id)
            mainWindowController?.updateTitle(projectName: appState?.selectedProject?.name)

        case .worktree(let id, _, _, _):
            manager.selectWorktree(id)

        case .window(let id, _, _, _):
            manager.selectWindow(id)

        case .action(let id, _, _):
            handlePaletteAction(id, manager: manager)
        }
    }

    private func handlePaletteAction(_ actionId: String, manager: WorkspaceManager) {
        switch actionId {
        case "action.create-worktree":
            // Prompt for branch name via a simple input dialog
            let alert = NSAlert()
            alert.messageText = "Create Worktree"
            alert.informativeText = "Enter a branch name:"
            alert.addButton(withTitle: "Create")
            alert.addButton(withTitle: "Cancel")

            let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            inputField.placeholderString = "feature/my-branch"
            alert.accessoryView = inputField

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let branchName = inputField.stringValue
                Task { @MainActor in
                    await manager.handleCreateWorktree(branchName: branchName)
                }
            }

        case "action.refresh":
            Task { @MainActor in
                await manager.coordinatedPoll()
            }

        case "action.open-project":
            showAddProjectPanel()

        default:
            break
        }
    }

    // MARK: - IPC Server

    private func startIPCServer(manager: WorkspaceManager) {
        let handler = IPCHandler(workspaceManager: manager)
        self.ipcHandler = handler

        let server = IPCServer { request in
            await handler.handle(request)
        }
        self.ipcServer = server

        Task {
            do {
                try await server.start()
            } catch {
                print("[Mori] Failed to start IPC server: \(error)")
            }
        }
    }

    // MARK: - Helpers

    /// Select the Nth visible worktree (1-indexed) across all non-collapsed projects.
    private func selectWorktreeByShortcut(index: Int) {
        guard let appState, let manager = workspaceManager else { return }
        var count = 0
        for project in appState.projects where !project.isCollapsed {
            let projectWorktrees = appState.worktrees.filter { $0.projectId == project.id }
            for worktree in projectWorktrees {
                count += 1
                if count == index {
                    manager.selectWorktree(worktree.id)
                    updateWindowTitle()
                    return
                }
            }
        }
    }

    private func updateWindowTitle() {
        mainWindowController?.updateTitle(
            projectName: appState?.selectedProject?.name,
            worktreeName: appState?.selectedWorktree?.branch ?? appState?.selectedWorktree?.name
        )
    }

    // MARK: - Settings (Cmd+,)

    @objc private func showSettingsMenuAction() {
        showSettingsWindow()
    }

    private func showSettingsWindow() {
        // If already open, bring to front
        if let existing = settingsWindowController?.window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        // Reload from disk so we always show the persisted state
        self.terminalSettings = TerminalSettings.load()

        // Wrapper view uses @State so SwiftUI properly tracks changes and
        // re-renders dependent UI (theme preview, etc.) on every edit.
        let settingsView = SettingsWindowContent(
            initial: self.terminalSettings,
            onChanged: { [weak self] newSettings in
                guard let self else { return }
                self.terminalSettings = newSettings
                self.terminalSettings.save()
                self.appState?.terminalSettings = newSettings
                self.terminalAreaController?.applySettings(self.terminalSettings)
                self.mainWindowController?.updateBackground(settings: self.terminalSettings)
                self.sidebarController?.updateAppearance(settings: self.terminalSettings)
                if let tmuxBackend = self.workspaceManager?.tmuxBackend {
                    let settings = self.terminalSettings
                    Task {
                        await TmuxThemeApplicator.apply(settings: settings, tmuxBackend: tmuxBackend)
                    }
                }
            }
        )

        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(hex: self.terminalSettings.theme.background)
        window.appearance = NSAppearance(named: self.terminalSettings.theme.isDark ? .darkAqua : .aqua)
        window.center()
        window.setFrameAutosaveName("MoriSettings")

        let controller = NSWindowController(window: window)
        self.settingsWindowController = controller
        controller.showWindow(nil)
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

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let windowId = userInfo["windowId"] as? String

        Task { @MainActor in
            // Bring app to front
            NSApp.activate(ignoringOtherApps: true)

            // Focus the relevant window if ID is available
            if let windowId {
                self.workspaceManager?.selectWindow(windowId)
            }
        }

        completionHandler()
    }

    /// Allow notifications to show even when the app is in foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - Settings Window Wrapper

/// Thin wrapper that gives SwiftUI `@State` ownership of the settings value
/// so pickers, sliders, and the theme preview all update in sync.
/// Also updates the settings window's own appearance when the theme changes.
private struct SettingsWindowContent: View {
    @State var settings: TerminalSettings
    var onChanged: (TerminalSettings) -> Void

    init(initial: TerminalSettings, onChanged: @escaping (TerminalSettings) -> Void) {
        self._settings = State(initialValue: initial)
        self.onChanged = onChanged
    }

    var body: some View {
        TerminalSettingsView(settings: $settings, onChanged: {
            onChanged(settings)
            updateSettingsWindowAppearance()
        })
    }

    private func updateSettingsWindowAppearance() {
        guard let window = NSApp.windows.first(where: { $0.frameAutosaveName == "MoriSettings" }) else { return }
        let theme = settings.theme
        window.backgroundColor = NSColor(hex: theme.background)
        window.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
    }
}
