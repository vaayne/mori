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
    private var sidebarController: SidebarHostingController?
    private var ipcServer: IPCServer?
    private var ipcHandler: IPCHandler?
    private var worktreeCreationController: WorktreeCreationController?
    private var settingsWindowController: NSWindowController?
    private var configFile: GhosttyConfigFile?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Task 3.8: Single instance check
        enforceSingleInstance()

        // Clean up legacy terminal settings from UserDefaults
        TerminalSettings.clearLegacy()

        // Set self as notification center delegate for click handling.
        // UNUserNotificationCenter requires a valid bundle proxy — guard for swift run.
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }

        // Initialize core dependencies
        let state = AppState()
        self.appState = state

        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Mori", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let storeURL = appSupport.appendingPathComponent("mori.json")
        let store = JSONStore(fileURL: storeURL)

        let projectRepo = ProjectRepository(store: store)
        let worktreeRepo = WorktreeRepository(store: store)
        let uiStateRepo = UIStateRepository(store: store)
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

        // Agent hooks are installed on-demand via Settings > Agents

        // Load persisted state
        try? manager.loadAll()

        // Create terminal area first — this initializes GhosttyApp and extracts theme
        let terminalArea = TerminalAreaViewController()
        terminalArea.onCreateSession = { [weak self] in
            guard let self else { return }
            if let manager = self.workspaceManager, manager.hasSelectedWorktree {
                // Worktree exists but session died — recreate it
                Task { await manager.reconnectCurrentSession() }
            } else {
                self.showAddProjectPanel()
            }
        }
        self.terminalAreaController = terminalArea

        // Wire ghostty keybinding actions to Mori's tmux-based implementation.
        // Ghostty maps keys to intents (new_tab, close_tab, etc.); Mori provides
        // the tmux backend. Users can customize keybindings via ghostty config.
        if let adapter = terminalArea.terminalHost as? GhosttyAdapter {
            adapter.actionHandler = { [weak self] action in
                self?.handleGhosttyAction(action)
            }
        }

        let themeInfo = terminalArea.themeInfo

        // Build the window with ghostty theme
        let windowController = MainWindowController(themeInfo: themeInfo)
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
            onShowCreatePanel: { [weak self] in
                self?.showCreateWorktreePanel()
            },
            onRemoveWorktree: { [weak manager] worktreeId in
                guard let manager else { return }
                Task { @MainActor in
                    await manager.removeWorktree(worktreeId: worktreeId)
                }
            },
            onRemoveProject: { [weak manager] projectId in
                guard let manager else { return }
                Task { @MainActor in
                    await manager.removeProject(projectId: projectId)
                }
            },
            onCloseWindow: { [weak manager] windowId in
                guard let manager else { return }
                Task { @MainActor in
                    await manager.closeWindow(windowId: windowId)
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
            },
            onToggleSidebarMode: { [weak manager] mode in
                manager?.setSidebarMode(mode)
            },
            onSetWorkflowStatus: { [weak manager] worktreeId, status in
                manager?.setWorkflowStatus(worktreeId: worktreeId, status: status)
            }
        )

        self.sidebarController = sidebarController
        sidebarController.updateAppearance(themeInfo: themeInfo)

        let splitVC = RootSplitViewController(
            sidebarController: sidebarController,
            contentController: terminalArea
        )
        self.rootSplitVC = splitVC

        windowController.onToggleSidebar = { [weak splitVC] in
            splitVC?.toggleSidebar()
        }

        windowController.onShowCreateWorktreePanel = { [weak self] in
            self?.showCreateWorktreePanel()
        }

        windowController.contentViewController = splitVC
        windowController.showWindow(nil)
        // Restore saved frame after all layout is complete
        windowController.restoreSavedFrame()
        NSApp.activate(ignoringOtherApps: true)

        // Wire terminal switch: when worktree selection changes, attach terminal
        manager.onTerminalSwitch = { [weak terminalArea] sessionName, workingDirectory in
            terminalArea?.attachToSession(sessionName: sessionName, workingDirectory: workingDirectory)
        }

        // Wire terminal detach: when session is killed, show empty state
        manager.onTerminalDetach = { [weak terminalArea, weak manager] in
            terminalArea?.hasSelectedWorktree = manager?.hasSelectedWorktree ?? false
            terminalArea?.detach()
        }

        // Restore previously saved UI state (project, worktree, window selection)
        manager.restoreState()

        // Set up the main menu bar
        setupMainMenu()

        // Set up command palette (Cmd+Shift+P)
        setupCommandPalette(appState: state, manager: manager)

        // Start IPC server for mori CLI communication
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

            // Apply ghostty theme colors to tmux (pane borders, status bar)
            if let terminalArea = self.terminalAreaController {
                await TmuxThemeApplicator.apply(
                    themeInfo: terminalArea.themeInfo,
                    tmuxBackend: manager.tmuxBackend
                )
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Save window frame and sidebar width before teardown
        mainWindowController?.saveFrame()
        rootSplitVC?.saveSidebarWidth()

        // Remove key monitor
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
        panel.message = .localized("Select a project folder")
        panel.prompt = .localized("Add Project")

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
                alert.messageText = .localized("Failed to add project")
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    // MARK: - Create Worktree Panel

    private func showCreateWorktreePanel() {
        guard let manager = workspaceManager, let state = appState else { return }

        guard let projectId = state.uiState.selectedProjectId,
              let project = state.projects.first(where: { $0.id == projectId }) else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = .localized("No Project Selected")
            alert.informativeText = .localized("Please select a project first.")
            alert.addButton(withTitle: .localized("OK"))
            alert.runModal()
            return
        }

        if worktreeCreationController == nil {
            let controller = WorktreeCreationController()

            controller.fetchBranches = { [weak manager] repoPath in
                guard let manager else { return [] }
                return try await manager.gitBackend.listBranches(repoPath: repoPath)
            }

            controller.onCreateWorktree = { [weak manager] request in
                guard let manager else { return }
                Task { @MainActor in
                    await manager.handleCreateWorktreeFromPanel(request)
                }
            }

            controller.onProjectChanged = { [weak self] newProjectId in
                guard let self else { return }
                self.appState?.uiState.selectedProjectId = newProjectId
                self.workspaceManager?.selectProject(newProjectId)
                self.refreshCreateWorktreePanel(for: newProjectId)
            }

            worktreeCreationController = controller
        }

        let controller = worktreeCreationController!

        let themeInfo = terminalAreaController?.themeInfo ?? .fallback
        controller.show(
            projects: state.projects,
            selectedProjectId: projectId,
            repoPath: project.repoRootPath,
            themeInfo: themeInfo
        )
    }

    /// Lightweight refresh when the user changes the project dropdown — only
    /// re-fetches branches for the new project without re-wiring callbacks or
    /// re-positioning the panel.
    private func refreshCreateWorktreePanel(for projectId: UUID) {
        guard let controller = worktreeCreationController,
              let state = appState,
              let project = state.projects.first(where: { $0.id == projectId }) else { return }
        controller.refresh(
            projects: state.projects,
            selectedProjectId: projectId,
            repoPath: project.repoRootPath
        )
    }

    // MARK: - Settings Window

    private func showSettingsWindow() {
        // If already open, bring to front
        if let existing = settingsWindowController?.window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let cf = GhosttyConfigFile()
        self.configFile = cf

        let themes = GhosttyConfigFile.availableThemes()
        let ghosttyDefaults = GhosttyConfigFile.defaultKeybinds()
        let themeInfo = terminalAreaController?.themeInfo ?? .fallback

        let settingsView = SettingsWindowContent(
            initial: readSettingsModel(from: cf),
            availableThemes: themes,
            ghosttyDefaults: ghosttyDefaults,
            initialAgentHooks: AgentHookModel(
                claudeEnabled: AgentHookConfigurator.isClaudeHookInstalled(),
                codexEnabled: AgentHookConfigurator.isCodexHookInstalled(),
                piEnabled: AgentHookConfigurator.isPiExtensionInstalled()
            ),
            onChanged: { [weak self] newModel in
                guard let self else { return }
                self.writeSettingsModel(newModel, to: cf)
                cf.save()
                self.reloadGhosttyConfig()
            },
            onOpenConfigFile: {
                NSWorkspace.shared.open(URL(fileURLWithPath: GhosttyConfigFile.configPath))
            },
            onAgentHookChanged: { newModel in
                Self.applyAgentHookChanges(newModel)
            }
        )

        let hostingController = NSHostingController(rootView: settingsView)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = themeInfo.background.cgColor
        let window = NSWindow(contentViewController: hostingController)
        window.title = .localized("Settings")
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = themeInfo.background
        window.appearance = NSAppearance(named: themeInfo.isDark ? .darkAqua : .aqua)
        window.center()
        window.setFrameAutosaveName("MoriSettings")

        let controller = NSWindowController(window: window)
        self.settingsWindowController = controller
        controller.showWindow(nil)
    }

    private func readSettingsModel(from cf: GhosttyConfigFile) -> GhosttySettingsModel {
        GhosttySettingsModel(
            fontFamily: cf.get("font-family") ?? "",
            fontSize: Int(cf.get("font-size") ?? "") ?? 13,
            theme: cf.get("theme") ?? "",
            cursorStyle: cf.get("cursor-style") ?? "block",
            cursorBlink: (cf.get("cursor-style-blink") ?? "true") != "false",
            backgroundOpacity: Double(cf.get("background-opacity") ?? "1.0") ?? 1.0,
            macosOptionAsAlt: cf.get("macos-option-as-alt") ?? "false",
            mouseHideWhileTyping: cf.get("mouse-hide-while-typing") == "true",
            mouseScrollMultiplier: Int(cf.get("mouse-scroll-multiplier") ?? "") ?? 1,
            copyOnSelect: cf.get("copy-on-select") ?? "false",
            windowPaddingBalance: cf.get("window-padding-balance") == "true",
            keybinds: cf.getAll("keybind")
        )
    }

    private func writeSettingsModel(_ model: GhosttySettingsModel, to cf: GhosttyConfigFile) {
        // Write keybinds (repeatable key)
        cf.setAll("keybind", values: model.keybinds)
        if model.fontFamily.isEmpty {
            cf.remove("font-family")
        } else {
            cf.set("font-family", value: model.fontFamily)
        }
        cf.set("font-size", value: "\(model.fontSize)")

        if model.theme.isEmpty {
            cf.remove("theme")
        } else {
            cf.set("theme", value: model.theme)
        }

        cf.set("cursor-style", value: model.cursorStyle)
        cf.set("cursor-style-blink", value: model.cursorBlink ? "true" : "false")
        cf.set("background-opacity", value: String(format: "%.2f", model.backgroundOpacity))
        cf.set("macos-option-as-alt", value: model.macosOptionAsAlt)
        cf.set("mouse-hide-while-typing", value: model.mouseHideWhileTyping ? "true" : "false")
        cf.set("mouse-scroll-multiplier", value: "\(model.mouseScrollMultiplier)")
        cf.set("copy-on-select", value: model.copyOnSelect)
        cf.set("window-padding-balance", value: model.windowPaddingBalance ? "true" : "false")
    }

    /// Reload ghostty config and sync theme to window/sidebar/tmux.
    private func reloadGhosttyConfig() {
        guard let adapter = terminalAreaController?.terminalHost as? GhosttyAdapter else { return }
        adapter.reloadConfig()

        let themeInfo = adapter.themeInfo
        mainWindowController?.window?.backgroundColor = themeInfo.background
        mainWindowController?.window?.appearance = NSAppearance(named: themeInfo.isDark ? .darkAqua : .aqua)
        sidebarController?.updateAppearance(themeInfo: themeInfo)
        terminalAreaController?.view.layer?.backgroundColor = themeInfo.background.cgColor

        // Update settings window appearance
        if let settingsWindow = settingsWindowController?.window {
            settingsWindow.backgroundColor = themeInfo.background
            settingsWindow.appearance = NSAppearance(named: themeInfo.isDark ? .darkAqua : .aqua)
            settingsWindow.contentViewController?.view.wantsLayer = true
            settingsWindow.contentViewController?.view.layer?.backgroundColor = themeInfo.background.cgColor
        }

        // Sync to tmux
        if let tmuxBackend = workspaceManager?.tmuxBackend {
            Task {
                await TmuxThemeApplicator.apply(themeInfo: themeInfo, tmuxBackend: tmuxBackend)
            }
        }
    }

    // MARK: - Main Menu (Task 5.4)

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // ── Mori (app) ──────────────────────────────────────────────
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: .localized("About Mori"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem(.localized("Open Project…"), action: #selector(openProjectMenuAction), key: "o", mods: [.command, .shift]))
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem(.localized("Settings…"), action: #selector(showSettingsMenuAction), key: ","))
        appMenu.addItem(menuItem(.localized("Reload Settings"), action: #selector(reloadSettingsMenuAction), key: ",", mods: [.command, .shift]))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: .localized("Hide Mori"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(menuItem(.localized("Hide Others"), action: #selector(NSApplication.hideOtherApplications(_:)), key: "h", mods: [.command, .option]))
        appMenu.addItem(withTitle: .localized("Show All"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: .localized("Quit Mori"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // ── Edit ─────────────────────────────────────────────────────
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: .localized("Edit"))
        editMenu.addItem(withTitle: .localized("Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: .localized("Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: .localized("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: .localized("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: .localized("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: .localized("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // ── Tmux (tabs, panes, tools) ────────────────────────────────
        let tmuxMenuItem = NSMenuItem()
        let tmuxMenu = NSMenu(title: .localized("Tmux"))

        tmuxMenu.addItem(menuItem(.localized("New Tab"), action: #selector(newTabMenuAction), key: "t"))
        tmuxMenu.addItem(menuItem(.localized("Close Pane"), action: #selector(closePaneMenuAction), key: "w"))
        tmuxMenu.addItem(.separator())
        tmuxMenu.addItem(menuItem(.localized("Next Tab"), action: #selector(nextTabMenuAction), key: "]", mods: [.command, .shift]))
        tmuxMenu.addItem(menuItem(.localized("Previous Tab"), action: #selector(previousTabMenuAction), key: "[", mods: [.command, .shift]))
        tmuxMenu.addItem(.separator())
        tmuxMenu.addItem(menuItem(.localized("Split Right"), action: #selector(splitRightMenuAction), key: "d"))
        tmuxMenu.addItem(menuItem(.localized("Split Down"), action: #selector(splitDownMenuAction), key: "d", mods: [.command, .shift]))
        tmuxMenu.addItem(.separator())
        tmuxMenu.addItem(menuItem(.localized("Next Pane"), action: #selector(nextPaneMenuAction), key: "]"))
        tmuxMenu.addItem(menuItem(.localized("Previous Pane"), action: #selector(previousPaneMenuAction), key: "["))
        tmuxMenu.addItem(menuItem(.localized("Toggle Pane Zoom"), action: #selector(togglePaneZoomMenuAction), key: "\r", mods: [.command, .shift]))
        tmuxMenu.addItem(menuItem(.localized("Equalize Panes"), action: #selector(equalizePanesMenuAction), key: "=", mods: [.command, .control]))
        tmuxMenu.addItem(.separator())
        tmuxMenu.addItem(menuItem(.localized("Open Lazygit"), action: #selector(openLazygitMenuAction), key: "g"))
        tmuxMenu.addItem(menuItem(.localized("Open Yazi"), action: #selector(openYaziMenuAction), key: "e"))

        tmuxMenuItem.submenu = tmuxMenu
        mainMenu.addItem(tmuxMenuItem)

        // ── Window (view + window merged) ────────────────────────────
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: .localized("Window"))
        windowMenu.addItem(menuItem(.localized("Toggle Sidebar"), action: #selector(toggleSidebarMenuAction), key: "b"))
        windowMenu.addItem(menuItem(.localized("Toggle Full Screen"), action: #selector(NSWindow.toggleFullScreen(_:)), key: "f", mods: [.command, .control]))
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: .localized("Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: .localized("Zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(menuItem(.localized("Close Window"), action: #selector(closeWindowMenuAction), key: "w", mods: [.command, .shift]))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    /// Helper to create an NSMenuItem with target = self.
    private func menuItem(
        _ title: String,
        action: Selector,
        key: String,
        mods: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = mods
        // Items targeting system selectors (NSWindow.toggleFullScreen, etc.)
        // should not set a target so they route via the responder chain.
        let systemActions: Set<String> = [
            NSStringFromSelector(#selector(NSWindow.toggleFullScreen(_:))),
            NSStringFromSelector(#selector(NSApplication.hideOtherApplications(_:))),
        ]
        if !systemActions.contains(NSStringFromSelector(action)) {
            item.target = self
        }
        return item
    }

    @objc private func openProjectMenuAction() {
        showAddProjectPanel()
    }

    @objc private func toggleSidebarMenuAction() {
        rootSplitVC?.toggleSidebar()
    }

    @objc private func newTabMenuAction() {
        guard let manager = workspaceManager else { return }
        Task { @MainActor in await manager.createNewWindow() }
    }

    @objc private func closePaneMenuAction() {
        guard let manager = workspaceManager else { return }
        Task { @MainActor in await manager.closeCurrentPane() }
    }

    @objc private func closeWindowMenuAction() {
        mainWindowController?.window?.close()
    }

    @objc private func openLazygitMenuAction() {
        guard let manager = workspaceManager else { return }
        Task { @MainActor in await manager.openToolWindow(command: "lazygit") }
    }

    @objc private func openYaziMenuAction() {
        guard let manager = workspaceManager else { return }
        Task { @MainActor in await manager.openToolWindow(command: "yazi") }
    }

    @objc private func splitRightMenuAction() {
        guard let manager = workspaceManager else { return }
        Task { @MainActor in await manager.splitCurrentPane(horizontal: true) }
    }

    @objc private func splitDownMenuAction() {
        guard let manager = workspaceManager else { return }
        Task { @MainActor in await manager.splitCurrentPane(horizontal: false) }
    }

    @objc private func nextTabMenuAction() {
        workspaceManager?.nextWindow()
    }

    @objc private func previousTabMenuAction() {
        workspaceManager?.previousWindow()
    }

    @objc private func nextPaneMenuAction() {
        guard let manager = workspaceManager else { return }
        Task { @MainActor in await manager.navigatePane(direction: .next) }
    }

    @objc private func previousPaneMenuAction() {
        guard let manager = workspaceManager else { return }
        Task { @MainActor in await manager.navigatePane(direction: .previous) }
    }

    @objc private func togglePaneZoomMenuAction() {
        guard let manager = workspaceManager else { return }
        Task { @MainActor in await manager.togglePaneZoom() }
    }

    @objc private func equalizePanesMenuAction() {
        guard let manager = workspaceManager else { return }
        Task { @MainActor in await manager.equalizePanes() }
    }


    // MARK: - Ghostty Action Handler

    /// Handle ghostty keybinding actions by redirecting to tmux via WorkspaceManager.
    /// Ghostty maps keys to abstract intents; this method provides the tmux implementation.
    private func handleGhosttyAction(_ action: GhosttyAppAction) {
        guard let manager = workspaceManager else { return }
        switch action {
        case .newTab:
            Task { await manager.createNewWindow() }
        case .closeTab:
            Task { await manager.closeCurrentPane() }
        case .gotoTab(let target):
            switch target {
            case .previous: manager.previousWindow()
            case .next: manager.nextWindow()
            case .last: manager.selectWindowByIndex(9)
            case .index(let n): manager.selectWindowByIndex(n)
            }
        case .newSplit(let dir):
            let horizontal = (dir == .right || dir == .left)
            Task { await manager.splitCurrentPane(horizontal: horizontal) }
        case .gotoSplit(let dir):
            let paneDir: PaneDirection
            switch dir {
            case .previous: paneDir = .previous
            case .next: paneDir = .next
            case .up: paneDir = .up
            case .down: paneDir = .down
            case .left: paneDir = .left
            case .right: paneDir = .right
            }
            Task { await manager.navigatePane(direction: paneDir) }
        case .resizeSplit(let dir, let amount):
            let paneDir: PaneDirection
            switch dir {
            case .up: paneDir = .up
            case .down: paneDir = .down
            case .left: paneDir = .left
            case .right: paneDir = .right
            }
            Task { await manager.resizePane(direction: paneDir, amount: Int(amount)) }
        case .equalizeSplits:
            Task { await manager.equalizePanes() }
        case .toggleSplitZoom:
            Task { await manager.togglePaneZoom() }
        case .newWindow:
            // Mori manages its own windows — ignore ghostty's new_window
            break
        case .closeWindow:
            mainWindowController?.window?.close()
        case .openConfig:
            showSettingsWindow()
        case .toggleFullscreen:
            mainWindowController?.window?.toggleFullScreen(nil)
        }
    }

    // MARK: - Tmux Missing Alert (Task 5.3)

    private func showTmuxMissingAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = .localized("tmux not found")
        alert.informativeText = .localized("Mori requires tmux to manage terminal sessions. Please install tmux and relaunch the app.\n\nInstall via Homebrew:\n  brew install tmux\n\nOr via MacPorts:\n  sudo port install tmux")
        alert.addButton(withTitle: .localized("OK"))
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

        // Register keyboard shortcuts that can't be expressed as menu key equivalents
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak palette, weak self] event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let key = event.charactersIgnoringModifiers ?? ""

            // Cmd+Shift+P: toggle command palette
            if mods == [.command, .shift], key == "P" || key == "p" {
                palette?.toggle()
                return nil
            }

            // Cmd+Shift+N: open worktree creation panel
            if mods == [.command, .shift], key == "N" || key == "n" {
                self?.showCreateWorktreePanel()
                return nil
            }

            // Cmd+1–9: select tmux window (tab) by index
            if mods == [.command], let digit = Int(key), digit >= 1, digit <= 9 {
                self?.workspaceManager?.selectWindowByIndex(digit)
                return nil
            }

            // Ctrl+Tab / Ctrl+Shift+Tab: cycle worktrees
            if event.keyCode == 48 { // Tab key
                if mods == [.control] {
                    self?.workspaceManager?.cycleWorktree(forward: true)
                    return nil
                }
                if mods == [.control, .shift] {
                    self?.workspaceManager?.cycleWorktree(forward: false)
                    return nil
                }
            }

            // Cmd+]/[: next/previous pane (keyCode 30 = ], 33 = [)
            if mods == [.command], event.keyCode == 30 {
                Task { @MainActor in await self?.workspaceManager?.navigatePane(direction: .next) }
                return nil
            }
            if mods == [.command], event.keyCode == 33 {
                Task { @MainActor in await self?.workspaceManager?.navigatePane(direction: .previous) }
                return nil
            }

            // Cmd+Shift+]/[: next/previous tab
            if mods == [.command, .shift], event.keyCode == 30 {
                self?.workspaceManager?.nextWindow()
                return nil
            }
            if mods == [.command, .shift], event.keyCode == 33 {
                self?.workspaceManager?.previousWindow()
                return nil
            }

            // Cmd+Alt+Arrows: directional pane navigation
            if mods == [.command, .option] {
                switch event.keyCode {
                case 126: // Up
                    Task { @MainActor in await self?.workspaceManager?.navigatePane(direction: .up) }
                    return nil
                case 125: // Down
                    Task { @MainActor in await self?.workspaceManager?.navigatePane(direction: .down) }
                    return nil
                case 123: // Left
                    Task { @MainActor in await self?.workspaceManager?.navigatePane(direction: .left) }
                    return nil
                case 124: // Right
                    Task { @MainActor in await self?.workspaceManager?.navigatePane(direction: .right) }
                    return nil
                default: break
                }
            }

            // Cmd+Ctrl+Arrows: resize pane
            if mods == [.command, .control] {
                switch event.keyCode {
                case 126: // Up
                    Task { @MainActor in await self?.workspaceManager?.resizePane(direction: .up) }
                    return nil
                case 125: // Down
                    Task { @MainActor in await self?.workspaceManager?.resizePane(direction: .down) }
                    return nil
                case 123: // Left
                    Task { @MainActor in await self?.workspaceManager?.resizePane(direction: .left) }
                    return nil
                case 124: // Right
                    Task { @MainActor in await self?.workspaceManager?.resizePane(direction: .right) }
                    return nil
                default: break
                }
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
            showCreateWorktreePanel()

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

    @objc private func reloadSettingsMenuAction() {
        terminalAreaController?.reloadConfig()
    }

    // MARK: - Agent Hook Settings

    private static func applyAgentHookChanges(_ model: AgentHookModel) {
        if model.claudeEnabled {
            AgentHookConfigurator.installClaudeHook()
        } else {
            AgentHookConfigurator.uninstallClaudeHook()
        }
        if model.codexEnabled {
            AgentHookConfigurator.installCodexHook()
        } else {
            AgentHookConfigurator.uninstallCodexHook()
        }
        if model.piEnabled {
            AgentHookConfigurator.installPiExtension()
        } else {
            AgentHookConfigurator.uninstallPiExtension()
        }
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
/// so all controls update in sync.
private struct SettingsWindowContent: View {
    @State var model: GhosttySettingsModel
    @State var agentHooks: AgentHookModel
    let availableThemes: [String]
    let ghosttyDefaults: [String]
    var onChanged: (GhosttySettingsModel) -> Void
    var onOpenConfigFile: () -> Void
    var onAgentHookChanged: (AgentHookModel) -> Void

    init(
        initial: GhosttySettingsModel,
        availableThemes: [String],
        ghosttyDefaults: [String] = [],
        initialAgentHooks: AgentHookModel = AgentHookModel(),
        onChanged: @escaping (GhosttySettingsModel) -> Void,
        onOpenConfigFile: @escaping () -> Void,
        onAgentHookChanged: @escaping (AgentHookModel) -> Void = { _ in }
    ) {
        self._model = State(initialValue: initial)
        self._agentHooks = State(initialValue: initialAgentHooks)
        self.availableThemes = availableThemes
        self.ghosttyDefaults = ghosttyDefaults
        self.onChanged = onChanged
        self.onOpenConfigFile = onOpenConfigFile
        self.onAgentHookChanged = onAgentHookChanged
    }

    var body: some View {
        GhosttySettingsView(
            model: $model,
            availableThemes: availableThemes,
            ghosttyDefaults: ghosttyDefaults,
            onChanged: { onChanged(model) },
            onOpenConfigFile: onOpenConfigFile,
            agentHooks: $agentHooks,
            onAgentHookChanged: onAgentHookChanged
        )
    }
}
