import AppKit
import MoriCore
import MoriGit
import MoriIPC
import MoriKeybindings
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
    private var companionToolController: CompanionToolPaneController?
    private var commandPaletteController: CommandPaletteController?
    private var rootSplitVC: RootSplitViewController?
    private var keyMonitor: Any?
    private var sidebarController: SidebarHostingController?
    private var ipcServer: IPCServer?
    private var ipcHandler: IPCHandler?
    private var worktreeCreationController: WorktreeCreationController?
    private let sidebarPaneOutputCache = PaneOutputCache()
    private var settingsWindowController: NSWindowController?
    private var configFile: GhosttyConfigFile?
    private var proxyApplyTask: Task<Void, Never>?
    private var tmuxThemeApplyTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var remoteConnectWizardController: RemoteConnectWizardController?
    private var updateController: UpdateController?
    private var agentDashboardPanel: AgentDashboardPanel?
    private var keyBindingStore: KeyBindingStore!
    private var configurableMenuItems: [String: NSMenuItem] = [:]
    private var keyMonitorActionMap: [String: () -> Void] = [:]
    private let tmuxThemeDebounceNanoseconds: UInt64 = 250_000_000
    private var companionToolState = CompanionToolPaneState()

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

        // Resolve app support directory using MoriPaths (handles dev/prod isolation)
        try? MoriPaths.ensureAppSupportDirectoryExists()
        let appSupport = MoriPaths.appSupportDirectory
        print("[Mori] Using app support directory: \(appSupport.path)")

        let storeURL = MoriPaths.fileURL(for: "mori.json")
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

        // Create terminal areas first — this initializes GhosttyApp and extracts theme.
        let terminalArea = TerminalAreaViewController()
        terminalArea.onCreateSession = { [weak self] in
            guard let self else { return }
            if let manager = self.workspaceManager, manager.hasSelectedWorktree {
                // Worktree exists but session died — auto-retry reconnect.
                self.startAutoReconnect()
            } else {
                self.showAddProjectPanel()
            }
        }
        self.terminalAreaController = terminalArea

        let companionTool = CompanionToolPaneController()
        self.companionToolController = companionTool

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
                self?.syncVisibleCompanionToolToSelection()
            },
            onSelectWorktree: { [weak manager, weak self] worktreeId in
                manager?.selectWorktree(worktreeId)
                self?.updateWindowTitle()
                self?.syncVisibleCompanionToolToSelection()
            },
            onSelectWindow: { [weak manager, weak self] windowId in
                manager?.selectWindow(windowId)
                self?.updateWindowTitle()
                self?.syncVisibleCompanionToolToSelection()
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
            onEditRemoteProject: { [weak self] projectId in
                self?.showEditRemoteCredentialsPanel(projectId: projectId)
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
            onRequestPaneOutput: { [weak self, weak manager] paneId, completion in
                guard let self, let manager else {
                    completion(nil)
                    return
                }
                // Check cache first
                if let cached = self.sidebarPaneOutputCache.get(paneId) {
                    completion(cached)
                    return
                }
                // Find the RuntimeWindow and its worktree to capture output
                let state = manager.appState
                guard let runtimeWindow = state.runtimeWindows.first(where: {
                    $0.activePaneId == paneId || $0.tmuxWindowId == paneId
                }),
                let worktree = state.worktrees.first(where: { $0.id == runtimeWindow.worktreeId }) else {
                    completion(nil)
                    return
                }
                let tmux = manager.tmuxBackendForWorktree(worktree)
                let targetPaneId = runtimeWindow.activePaneId ?? manager.rawTmuxWindowId(from: runtimeWindow)
                Task {
                    let output = try? await tmux.capturePaneOutput(paneId: targetPaneId, lineCount: 8)
                    if let output {
                        self.sidebarPaneOutputCache.set(paneId, output: output)
                    }
                    completion(output)
                }
            },
            onSendKeys: { [weak manager] paneId, text in
                guard let manager else { return }
                let state = manager.appState
                guard let runtimeWindow = state.runtimeWindows.first(where: {
                    $0.activePaneId == paneId || $0.tmuxWindowId == paneId
                }),
                let worktree = state.worktrees.first(where: { $0.id == runtimeWindow.worktreeId }),
                let sessionName = worktree.tmuxSessionName else { return }
                let tmux = manager.tmuxBackendForWorktree(worktree)
                let targetPaneId = runtimeWindow.activePaneId ?? manager.rawTmuxWindowId(from: runtimeWindow)
                Task {
                    try? await tmux.sendKeys(sessionId: sessionName, paneId: targetPaneId, keys: text)
                }
            },
            onUpdateProject: { [weak manager] project in
                manager?.updateProject(project)
            }
        )

        self.sidebarController = sidebarController
        sidebarController.updateAppearance(themeInfo: themeInfo)

        let splitVC = RootSplitViewController(
            sidebarController: sidebarController,
            contentController: terminalArea,
            companionController: companionTool
        )
        self.rootSplitVC = splitVC
        companionToolState.width = splitVC.currentCompanionWidth
        splitVC.onCompanionWidthChanged = { [weak self] width in
            self?.companionToolState.width = width
        }
        splitVC.updateCompanionPane(state: companionToolState)

        windowController.onToggleSidebar = { [weak splitVC] in
            splitVC?.toggleSidebar()
        }
        windowController.onToggleFiles = { [weak self] in
            self?.toggleCompanionTool(.yazi)
        }
        windowController.onToggleGit = { [weak self] in
            self?.toggleCompanionTool(.lazygit)
        }
        windowController.onSplitRight = { [weak self] in
            self?.splitRightMenuAction()
        }
        windowController.onSplitDown = { [weak self] in
            self?.splitDownMenuAction()
        }

        windowController.onShowCreateWorktreePanel = { [weak self] in
            self?.showCreateWorktreePanel()
        }
        windowController.onWindowAppearanceInvalidated = { [weak self, weak terminalArea, weak windowController] in
            guard let self,
                  let adapter = terminalArea?.terminalHost as? GhosttyAdapter,
                  let window = windowController?.window else { return }
            adapter.syncWorkspaceWindowAppearance(window)
            self.refreshGhosttyThemeBackgrounds(themeInfo: adapter.themeInfo)
        }

        windowController.contentViewController = splitVC
        windowController.showWindow(nil)
        if let adapter = terminalArea.terminalHost as? GhosttyAdapter,
           let window = windowController.window {
            adapter.syncWorkspaceWindowAppearance(window)
        }
        companionTool.updateAppearance(themeInfo: themeInfo, isKeyWindow: windowController.window?.isKeyWindow ?? true)
        // Restore saved frame after all layout is complete
        windowController.restoreSavedFrame()
        NSApp.activate(ignoringOtherApps: true)

        // Initialize update system (after window exists so hasUnobtrusiveTarget works)
        let update = UpdateController()
        self.updateController = update
        update.startUpdater()
        windowController.addUpdateAccessory(viewModel: update.viewModel)

        // Wire terminal switch: when worktree selection changes, attach terminal
        manager.onTerminalSwitch = { [weak terminalArea] sessionName, workingDirectory, location in
            terminalArea?.attachToSession(
                sessionName: sessionName,
                workingDirectory: workingDirectory,
                location: location
            )
        }

        // Wire terminal detach: when session is killed, show empty state
        manager.onTerminalDetach = { [weak terminalArea, weak manager] in
            terminalArea?.hasSelectedWorktree = manager?.hasSelectedWorktree ?? false
            terminalArea?.detach()
        }

        // Wire session created: apply proxy env vars after tmux server starts
        manager.onSessionCreated = { [weak self] tmuxBackend in
            guard self != nil else { return }
            let model = ProxySettingsApplicator.load()
            await ProxySettingsApplicator.apply(model, tmuxBackend: tmuxBackend)

            // Apply theme (including status bar off) to the newly created session
            if let self {
                self.scheduleTmuxThemeApply(immediate: true, tmuxBackend: tmuxBackend)
            }
        }

        // Restore previously saved UI state (project, worktree, window selection)
        manager.restoreState()

        // Initialize key binding store
        let keybindingsURL = MoriPaths.fileURL(for: "keybindings.json")
        let keyBindingRepo = KeyBindingRepository(fileURL: keybindingsURL)
        keyBindingStore = KeyBindingStore(storage: keyBindingRepo)
        keyBindingStore.onBindingsChanged = { [weak self] in
            self?.rebuildMenuKeyBindings()
        }

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

            if let terminalArea = self.terminalAreaController,
               let tmuxPath = try? await manager.tmuxBackend.resolvedBinaryPath() {
                terminalArea.tmuxBinaryPath = tmuxPath
            }

            // On first launch, create a default Home workspace at $HOME
            await manager.createHomeWorkspaceIfNeeded()
            manager.restoreState()

            // Initial runtime state load
            await manager.refreshRuntimeState()

            // Start coordinated polling (tmux + git status on each 5s tick)
            manager.startPolling()

            // Apply ghostty theme colors to tmux (pane borders, status bar)
            self.scheduleTmuxThemeApply(immediate: true, tmuxBackend: manager.tmuxBackend)

            // Apply proxy environment variables to tmux
            self.applyProxyToTmux()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Save window frame and split widths before teardown
        mainWindowController?.saveFrame()
        rootSplitVC?.saveSidebarWidth()
        rootSplitVC?.saveCompanionWidth()

        // Remove key monitor
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }

        // Stop IPC server
        IPCServer.removeSocketFile()
        if let server = ipcServer {
            Task { await server.stop() }
        }

        // Stop coordinated polling
        workspaceManager?.stopPolling()
        reconnectTask?.cancel()
        reconnectTask = nil

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
        showLocalProjectPanel()
    }

    private func showLocalProjectPanel() {
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

    private func showRemoteConnectWizard() {
        let wizard = RemoteConnectWizardController()
        wizard.onSubmit = { [weak self] (input: RemoteConnectInput) async -> Result<Void, any Error> in
            guard let self else {
                return .failure(NSError(domain: "Mori", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Window closed.",
                ]))
            }
            guard let manager = self.workspaceManager else {
                return .failure(NSError(domain: "Mori", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Workspace manager unavailable.",
                ]))
            }

            do {
                let project = try await manager.addRemoteProject(
                    host: input.host,
                    path: input.path,
                    user: input.user,
                    port: input.port,
                    authMethod: input.authMethod,
                    password: input.password
                )
                self.mainWindowController?.updateTitle(projectName: project.name)
                self.scheduleAttachExistingRemoteSessionPrompt(projectId: project.id)
                return .success(())
            } catch {
                return .failure(error)
            }
        }
        remoteConnectWizardController = wizard
        wizard.present(over: mainWindowController?.window)
    }

    private func scheduleAttachExistingRemoteSessionPrompt(projectId: UUID) {
        Task { @MainActor [weak self] in
            guard let self,
                  let window = self.mainWindowController?.window else { return }

            // Wait until the remote-connect wizard sheet has been dismissed.
            var attempts = 0
            while window.attachedSheet != nil, attempts < 40 {
                attempts += 1
                try? await Task.sleep(nanoseconds: 50_000_000)
            }

            await self.offerAttachToExistingRemoteSessionIfNeeded(projectId: projectId)
        }
    }

    private func offerAttachToExistingRemoteSessionIfNeeded(projectId: UUID) async {
        guard let manager = workspaceManager,
              let state = appState,
              let project = state.projects.first(where: { $0.id == projectId }),
              case .ssh = project.resolvedLocation else { return }

        let sessionNames = await manager.listRemoteSessionNames(projectId: projectId)
        guard !sessionNames.isEmpty else { return }

        guard let chosen = await promptForRemoteSessionAttachment(
            projectName: project.name,
            sessionNames: sessionNames
        ) else { return }

        do {
            try await manager.attachMainWorktreeToRemoteSession(
                projectId: projectId,
                sessionName: chosen
            )
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = .localized("Failed to attach session")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func promptForRemoteSessionAttachment(
        projectName: String,
        sessionNames: [String]
    ) async -> String? {
        guard let window = mainWindowController?.window else { return nil }

        let createNewOption = String.localized("Create New Managed Session")
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 26), pullsDown: false)
        popup.addItem(withTitle: createNewOption)
        popup.menu?.addItem(.separator())
        for name in sessionNames {
            popup.addItem(withTitle: name)
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = .localized("Attach Existing tmux Session")
        alert.informativeText = String(
            format: .localized("Remote host has active tmux sessions. Choose one to attach for \"%@\"."),
            projectName
        )
        alert.accessoryView = popup
        alert.addButton(withTitle: .localized("Attach Session"))
        alert.addButton(withTitle: .localized("Skip"))

        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                guard response == .alertFirstButtonReturn,
                      let selected = popup.selectedItem?.title,
                      selected != createNewOption else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: selected)
            }
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

    private func showEditRemoteCredentialsPanel(projectId: UUID) {
        guard let state = appState,
              let project = state.projects.first(where: { $0.id == projectId }),
              case .ssh(let ssh) = project.resolvedLocation,
              let window = mainWindowController?.window else { return }

        let methodAlert = NSAlert()
        methodAlert.alertStyle = .informational
        methodAlert.messageText = .localized("Update Remote Credentials")
        methodAlert.informativeText = .localized("Host: \(ssh.target)")
        methodAlert.addButton(withTitle: .localized("SSH Key / Agent"))
        methodAlert.addButton(withTitle: .localized("Password"))
        methodAlert.addButton(withTitle: .localized("Cancel"))

        methodAlert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:
                self.applyRemoteAuthUpdate(projectId: projectId, authMethod: .publicKey, password: nil)
            case .alertSecondButtonReturn:
                self.promptForRemotePassword(projectId: projectId, hostDisplay: ssh.target)
            default:
                break
            }
        }
    }

    private func promptForRemotePassword(projectId: UUID, hostDisplay: String) {
        guard let window = mainWindowController?.window else { return }

        let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        passwordField.placeholderString = .localized("Password")

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = .localized("Password Authentication")
        alert.informativeText = .localized("Enter SSH password for \(hostDisplay)")
        alert.accessoryView = passwordField
        alert.addButton(withTitle: .localized("Save & Reconnect"))
        alert.addButton(withTitle: .localized("Cancel"))

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let password = passwordField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            self?.applyRemoteAuthUpdate(projectId: projectId, authMethod: .password, password: password)
        }
    }

    private func applyRemoteAuthUpdate(
        projectId: UUID,
        authMethod: SSHAuthMethod,
        password: String?
    ) {
        guard let manager = workspaceManager else { return }
        Task { @MainActor in
            do {
                try await manager.updateRemoteAuth(
                    projectId: projectId,
                    authMethod: authMethod,
                    password: password
                )
            } catch {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = .localized("Failed to update remote credentials")
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

            controller.fetchBranches = { [weak manager] projectId, repoPath in
                guard let manager else { return [] }
                return try await manager.listBranches(projectId: projectId, repoPathHint: repoPath)
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

        let store = self.keyBindingStore!
        let settingsView = SettingsWindowContent(
            initial: readSettingsModel(from: cf),
            availableThemes: themes,
            ghosttyDefaults: ghosttyDefaults,
            initialAgentHooks: AgentHookModel(
                claudeEnabled: AgentHookConfigurator.isClaudeHookInstalled(),
                codexEnabled: AgentHookConfigurator.isCodexHookInstalled(),
                piEnabled: AgentHookConfigurator.isPiExtensionInstalled(),
                droidEnabled: AgentHookConfigurator.isDroidHookInstalled()
            ),
            initialProxy: ProxySettingsApplicator.load(),
            initialTools: ToolSettings.load(),
            onChanged: { [weak self] newModel in
                guard let self else { return }
                self.writeSettingsModel(newModel, to: cf)
                cf.save()
                self.reloadGhosttyConfig()
            },
            onOpenConfigFile: {
                GhosttyConfigFile.ensureConfigFileExists()
                GhosttyConfigFile.normalizePermissions()
                let configURL = URL(fileURLWithPath: GhosttyConfigFile.configPath)
                if let textEditURL = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: "com.apple.TextEdit"
                ) {
                    NSWorkspace.shared.open(
                        [configURL],
                        withApplicationAt: textEditURL,
                        configuration: NSWorkspace.OpenConfiguration()
                    ) { _, _ in }
                } else {
                    NSWorkspace.shared.open(configURL)
                }
            },
            onAgentHookChanged: { newModel in
                Self.applyAgentHookChanges(newModel)
            },
            onProxyApply: { [weak self] newModel in
                ProxySettingsApplicator.save(newModel)
                self?.applyProxyToTmux()
            },
            onSystemProxyDetect: {
                ProxySettingsApplicator.readSystemProxy()
            },
            onToolSettingsChanged: { [weak self] newModel in
                ToolSettings.save(newModel)
                Task { @MainActor [weak self] in
                    guard let self,
                          let manager = self.workspaceManager,
                          let tmuxPath = try? await manager.tmuxBackend.resolvedBinaryPath() else { return }
                    self.terminalAreaController?.tmuxBinaryPath = tmuxPath
                }
            },
            keyBindings: store.bindings,
            keyBindingDefaults: KeyBindingDefaults.all,
            onKeyBindingValidate: { binding in
                store.validate(binding)
            },
            onKeyBindingUpdate: { binding in
                store.update(binding)
            },
            onKeyBindingReset: { id in
                store.resetBinding(id: id)
            },
            onKeyBindingResetAll: {
                store.resetAll()
            },
            keyBindingsRefresh: {
                store.bindings
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
        if let adapter = terminalAreaController?.terminalHost as? GhosttyAdapter {
            adapter.syncThemedWindowAppearance(window)
        } else {
            window.backgroundColor = themeInfo.background
            window.appearance = NSAppearance(named: themeInfo.isDark ? .darkAqua : .aqua)
        }
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
            backgroundOpacityCells: cf.get("background-opacity-cells") == "true",
            backgroundBlur: GhosttyBackgroundBlur(configValue: cf.get("background-blur") ?? "false"),
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
        cf.set("background-opacity-cells", value: model.backgroundOpacityCells ? "true" : "false")
        cf.set("background-blur", value: model.backgroundBlur.configValue)
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
        if let window = mainWindowController?.window {
            adapter.syncWorkspaceWindowAppearance(window)
        }
        refreshGhosttyThemeBackgrounds(themeInfo: themeInfo)

        refreshSettingsWindowAppearance(adapter: adapter, themeInfo: themeInfo)

        // Update agent dashboard appearance
        agentDashboardPanel?.updateAppearance(themeInfo: themeInfo)

        // Sync to tmux
        if let tmuxBackend = workspaceManager?.tmuxBackend {
            scheduleTmuxThemeApply(immediate: false, tmuxBackend: tmuxBackend)
        }
    }

    private func scheduleTmuxThemeApply(immediate: Bool, tmuxBackend: TmuxBackend) {
        tmuxThemeApplyTask?.cancel()
        let delayNanoseconds = immediate ? 0 : tmuxThemeDebounceNanoseconds
        tmuxThemeApplyTask = Task { [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled,
                  let themeInfo = self?.terminalAreaController?.themeInfo else { return }
            await TmuxThemeApplicator.apply(themeInfo: themeInfo, tmuxBackend: tmuxBackend)
        }
    }

    private func refreshGhosttyThemeBackgrounds(themeInfo: GhosttyThemeInfo) {
        let isKeyWindow = mainWindowController?.window?.isKeyWindow ?? true
        sidebarController?.updateAppearance(themeInfo: themeInfo)
        terminalAreaController?.updateAppearance(themeInfo: themeInfo, isKeyWindow: isKeyWindow)
        companionToolController?.updateAppearance(themeInfo: themeInfo, isKeyWindow: isKeyWindow)
    }

    private func refreshSettingsWindowAppearance(adapter: GhosttyAdapter, themeInfo: GhosttyThemeInfo) {
        guard let settingsWindow = settingsWindowController?.window else { return }
        adapter.syncThemedWindowAppearance(settingsWindow)
        settingsWindow.contentViewController?.view.wantsLayer = true
        settingsWindow.contentViewController?.view.layer?.backgroundColor = themeInfo.background.cgColor
    }

    // MARK: - Proxy

    /// Apply saved proxy settings to tmux, cancelling any in-flight apply.
    private func applyProxyToTmux() {
        proxyApplyTask?.cancel()
        proxyApplyTask = Task { [weak self] in
            guard let tmuxBackend = self?.workspaceManager?.tmuxBackend else { return }
            let model = ProxySettingsApplicator.load()
            await ProxySettingsApplicator.apply(model, tmuxBackend: tmuxBackend)
        }
    }

    // MARK: - Main Menu (Task 5.4)

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        configurableMenuItems.removeAll()

        // ── Mori (app) ──────────────────────────────────────────────
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: .localized("About Mori"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let checkForUpdatesItem = NSMenuItem(title: .localized("Check for Updates…"), action: #selector(checkForUpdatesMenuAction), keyEquivalent: "")
        checkForUpdatesItem.target = self
        appMenu.addItem(checkForUpdatesItem)
        let installCLIItem = NSMenuItem(title: cliSymlinkExists() ? .localized("Uninstall CLI…") : .localized("Install CLI…"), action: #selector(installOrUninstallCLIMenuAction), keyEquivalent: "")
        installCLIItem.target = self
        installCLIMenuItem = installCLIItem
        appMenu.addItem(installCLIItem)
        appMenu.addItem(.separator())
        appMenu.addItem(configurableMenuItem("other.openProject", title: .localized("Open Project…"), action: #selector(openProjectMenuAction)))
        appMenu.addItem(configurableMenuItem("other.remoteConnect", title: .localized("Remote Connect…"), action: #selector(remoteConnectMenuAction)))
        appMenu.addItem(.separator())
        appMenu.addItem(configurableMenuItem("settings.open", title: .localized("Settings…"), action: #selector(showSettingsMenuAction)))
        appMenu.addItem(configurableMenuItem("settings.reload", title: .localized("Reload Settings"), action: #selector(reloadSettingsMenuAction)))
        appMenu.addItem(.separator())
        // Locked: Hide, Hide Others, Show All, Quit
        appMenu.addItem(withTitle: .localized("Hide Mori"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(menuItem(.localized("Hide Others"), action: #selector(NSApplication.hideOtherApplications(_:)), key: "h", mods: [.command, .option]))
        appMenu.addItem(withTitle: .localized("Show All"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: .localized("Quit Mori"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // ── Edit (all locked — responder chain) ──────────────────────
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

        tmuxMenu.addItem(configurableMenuItem("tabs.newTab", title: .localized("New Tab"), action: #selector(newTabMenuAction)))
        tmuxMenu.addItem(configurableMenuItem("tabs.closeTab", title: .localized("Close Pane"), action: #selector(closePaneMenuAction)))
        tmuxMenu.addItem(.separator())
        tmuxMenu.addItem(configurableMenuItem("tabs.nextTab", title: .localized("Next Tab"), action: #selector(nextTabMenuAction)))
        tmuxMenu.addItem(configurableMenuItem("tabs.previousTab", title: .localized("Previous Tab"), action: #selector(previousTabMenuAction)))
        tmuxMenu.addItem(.separator())
        tmuxMenu.addItem(configurableMenuItem("panes.splitRight", title: .localized("Split Right"), action: #selector(splitRightMenuAction)))
        tmuxMenu.addItem(configurableMenuItem("panes.splitDown", title: .localized("Split Down"), action: #selector(splitDownMenuAction)))
        tmuxMenu.addItem(.separator())
        tmuxMenu.addItem(configurableMenuItem("panes.nextPane", title: .localized("Next Pane"), action: #selector(nextPaneMenuAction)))
        tmuxMenu.addItem(configurableMenuItem("panes.previousPane", title: .localized("Previous Pane"), action: #selector(previousPaneMenuAction)))
        tmuxMenu.addItem(configurableMenuItem("panes.toggleZoom", title: .localized("Toggle Pane Zoom"), action: #selector(togglePaneZoomMenuAction)))
        tmuxMenu.addItem(configurableMenuItem("panes.equalize", title: .localized("Equalize Panes"), action: #selector(equalizePanesMenuAction)))
        tmuxMenu.addItem(.separator())
        tmuxMenu.addItem(configurableMenuItem("tools.lazygit", title: .localized("Open Lazygit"), action: #selector(openLazygitMenuAction)))
        tmuxMenu.addItem(configurableMenuItem("tools.yazi", title: .localized("Open Yazi"), action: #selector(openYaziMenuAction)))

        tmuxMenuItem.submenu = tmuxMenu
        mainMenu.addItem(tmuxMenuItem)

        // ── Window (view + window merged) ────────────────────────────
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: .localized("Window"))
        windowMenu.addItem(configurableMenuItem("window.toggleSidebar", title: .localized("Toggle Sidebar"), action: #selector(toggleSidebarMenuAction)))
        // Locked: Toggle Full Screen (responder chain)
        windowMenu.addItem(menuItem(.localized("Toggle Full Screen"), action: #selector(NSWindow.toggleFullScreen(_:)), key: "f", mods: [.command, .control]))
        windowMenu.addItem(.separator())
        // Locked: Minimize, Zoom
        windowMenu.addItem(withTitle: .localized("Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: .localized("Zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(configurableMenuItem("window.closeWindow", title: .localized("Close Window"), action: #selector(closeWindowMenuAction)))
        windowMenu.addItem(.separator())
        windowMenu.addItem(configurableMenuItem("other.agentDashboard", title: .localized("Agent Dashboard"), action: #selector(toggleAgentDashboardAction)))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    /// Helper to create an NSMenuItem with target = self (for locked/system items).
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

    /// Create a configurable menu item whose shortcut is driven by the key binding store.
    /// The item is tracked in `configurableMenuItems` so it can be updated when bindings change.
    private func configurableMenuItem(
        _ bindingId: String,
        title: String,
        action: Selector
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self

        if let binding = keyBindingStore.binding(for: bindingId),
           let shortcut = binding.shortcut {
            item.keyEquivalent = shortcut.menuKeyEquivalent
            item.keyEquivalentModifierMask = shortcut.menuModifierMask
        }

        configurableMenuItems[bindingId] = item
        return item
    }

    /// Update all configurable menu items to reflect current key binding store state.
    private func rebuildMenuKeyBindings() {
        for binding in keyBindingStore.bindings where !binding.isLocked {
            guard let menuItem = configurableMenuItems[binding.id] else { continue }
            if let shortcut = binding.shortcut {
                menuItem.keyEquivalent = shortcut.menuKeyEquivalent
                menuItem.keyEquivalentModifierMask = shortcut.menuModifierMask
            } else {
                menuItem.keyEquivalent = ""
                menuItem.keyEquivalentModifierMask = []
            }
        }
    }

    @objc private func checkForUpdatesMenuAction() {
        updateController?.checkForUpdates()
    }

    // MARK: - CLI Installation

    private static let cliSymlinkPath = "/usr/local/bin/mori"
    private weak var installCLIMenuItem: NSMenuItem?

    private func cliBinaryPath() -> String? {
        let fm = FileManager.default
        guard let bundlePath = Bundle.main.executablePath else { return nil }
        let bundleDir = (bundlePath as NSString).deletingLastPathComponent

        // 1. App bundle: .../Mori.app/Contents/MacOS/bin/mori
        let bundleCLI = (bundleDir as NSString).appendingPathComponent("bin/mori")
        if fm.fileExists(atPath: bundleCLI) { return bundleCLI }

        // 2. Dev build: walk up from executable until we find .build-cli/
        var dir = bundleDir
        for _ in 0..<5 {
            dir = (dir as NSString).deletingLastPathComponent
            for config in ["release", "debug"] {
                let devCLI = (dir as NSString).appendingPathComponent(".build-cli/\(config)/mori")
                if fm.fileExists(atPath: devCLI) { return devCLI }
            }
        }

        return nil
    }

    private func cliSymlinkExists() -> Bool {
        if case .ours = cliSymlinkState() { return true }
        return false
    }

    private enum CLISymlinkState {
        case none                      // nothing at the path
        case ours                      // symlink → our bundle CLI
        case foreign(destination: String) // symlink → somewhere else
        case regularFile               // not a symlink at all
    }

    private func cliSymlinkState() -> CLISymlinkState {
        let fm = FileManager.default
        guard fm.fileExists(atPath: Self.cliSymlinkPath) else { return .none }
        guard let dest = try? fm.destinationOfSymbolicLink(atPath: Self.cliSymlinkPath) else {
            return .regularFile
        }
        if let ourCLI = cliBinaryPath(),
           URL(fileURLWithPath: dest).standardized == URL(fileURLWithPath: ourCLI).standardized {
            return .ours
        }
        return .foreign(destination: dest)
    }

    @objc private func installOrUninstallCLIMenuAction() {
        if cliSymlinkExists() {
            uninstallCLI()
        } else {
            installCLI()
        }
    }

    private func installCLI() {
        guard let cliPath = cliBinaryPath() else {
            showCLIAlert(
                style: .warning,
                message: .localized("CLI binary not found in application bundle."),
                info: .localized("Please reinstall Mori to restore the CLI binary.")
            )
            return
        }

        let symlinkPath = Self.cliSymlinkPath
        let binDir = (symlinkPath as NSString).deletingLastPathComponent

        // Guard against overwriting a foreign symlink or regular file
        switch cliSymlinkState() {
        case .foreign(let destination):
            let proceed = showCLIConfirmation(
                message: .localized("Existing CLI found"),
                info: String(format: .localized("%@ currently points to %@. Replace it?"), symlinkPath, destination)
            )
            guard proceed else { return }
        case .regularFile:
            showCLIAlert(
                style: .warning,
                message: .localized("CLI installation failed."),
                info: String(format: .localized("A non-symlink file already exists at %@. Please remove it manually."), symlinkPath)
            )
            return
        case .ours, .none:
            break
        }

        let script = "mkdir -p \(shellEscaped(binDir)) && rm -f \(shellEscaped(symlinkPath)) && ln -s \(shellEscaped(cliPath)) \(shellEscaped(symlinkPath))"

        let result = runWithAdminPrivileges(script: script)
        switch result {
        case .success:
            showCLIAlert(
                style: .informational,
                message: .localized("CLI installed successfully."),
                info: String(format: .localized("The `mori` command is now available at %@."), symlinkPath)
            )
        case .cancelled:
            break
        case .failure(let msg):
            showCLIAlert(style: .warning, message: .localized("CLI installation failed."), info: msg)
        }
        updateCLIMenuItemTitle()
    }

    private func uninstallCLI() {
        let symlinkPath = Self.cliSymlinkPath
        let script = "rm -f \(shellEscaped(symlinkPath))"

        let result = runWithAdminPrivileges(script: script)
        switch result {
        case .success:
            showCLIAlert(
                style: .informational,
                message: .localized("CLI uninstalled successfully."),
                info: String(format: .localized("The symlink at %@ has been removed."), symlinkPath)
            )
        case .cancelled:
            break
        case .failure(let msg):
            showCLIAlert(style: .warning, message: .localized("CLI uninstallation failed."), info: msg)
        }
        updateCLIMenuItemTitle()
    }

    private func updateCLIMenuItemTitle() {
        installCLIMenuItem?.title = cliSymlinkExists() ? .localized("Uninstall CLI…") : .localized("Install CLI…")
    }

    private func shellEscaped(_ s: String) -> String {
        SSHCommandSupport.shellEscape(s)
    }

    private enum AdminPrivilegeResult {
        case success
        case cancelled
        case failure(String)
    }

    private func runWithAdminPrivileges(script: String) -> AdminPrivilegeResult {
        let escapedScript = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "do shell script \"\(escapedScript)\" with administrator privileges"
        var error: NSDictionary?
        guard let scriptObj = NSAppleScript(source: appleScript) else {
            return .failure("Failed to create AppleScript.")
        }
        _ = scriptObj.executeAndReturnError(&error)
        if error == nil { return .success }
        // Error code -128 = user clicked Cancel
        if let errorNumber = error?[NSAppleScript.errorNumber] as? Int, errorNumber == -128 {
            return .cancelled
        }
        let msg = error?[NSAppleScript.errorMessage] as? String ?? .localized("Failed to create symlink. Please check your permissions.")
        return .failure(msg)
    }

    private func showCLIAlert(style: NSAlert.Style, message: String, info: String) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = message
        alert.informativeText = info
        alert.addButton(withTitle: .localized("OK"))
        alert.runModal()
    }

    private func showCLIConfirmation(message: String, info: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = info
        alert.addButton(withTitle: .localized("Replace"))
        alert.addButton(withTitle: .localized("Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    @objc private func openProjectMenuAction() {
        showAddProjectPanel()
    }

    @objc private func remoteConnectMenuAction() {
        showRemoteConnectWizard()
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

    @objc private func toggleAgentDashboardAction() {
        if agentDashboardPanel == nil, let manager = workspaceManager {
            agentDashboardPanel = AgentDashboardPanel(
                workspaceManager: manager,
                paneOutputCache: PaneOutputCache()
            )
        }
        agentDashboardPanel?.toggle()
        // Sync appearance with Ghostty terminal theme
        let themeInfo = terminalAreaController?.themeInfo ?? .fallback
        agentDashboardPanel?.updateAppearance(themeInfo: themeInfo)
    }

    private func toggleCompanionTool(_ tool: CompanionTool) {
        let sameToolVisible = companionToolState.activeTool == tool && companionToolState.isVisible
        let toolIsFocused = companionToolController?.isFocused(in: mainWindowController?.window) == true

        if sameToolVisible && toolIsFocused {
            closeCompanionTool()
            terminalAreaController?.focusCurrentSurface()
            return
        }

        guard let manager = workspaceManager,
              let context = manager.companionToolLaunchContext() else {
            NSSound.beep()
            return
        }

        showCompanionTool(tool, context: context)
    }

    private func closeCompanionTool() {
        companionToolState.activeTool = nil
        companionToolState.presentation = .closed
        rootSplitVC?.updateCompanionPane(state: companionToolState)
    }

    private func showCompanionTool(_ tool: CompanionTool, context: CompanionToolLaunchContext, focus: Bool = true) {
        companionToolState.activeTool = tool
        companionToolState.presentation = .docked
        companionToolController?.show(tool: tool, context: context, focus: focus)
        rootSplitVC?.updateCompanionPane(state: companionToolState)
    }

    private func syncVisibleCompanionToolToSelection() {
        guard companionToolState.isVisible,
              let tool = companionToolState.activeTool,
              let manager = workspaceManager else {
            return
        }

        guard let context = manager.companionToolLaunchContext() else {
            closeCompanionTool()
            return
        }

        showCompanionTool(tool, context: context, focus: false)
    }

    @objc private func openLazygitMenuAction() {
        toggleCompanionTool(.lazygit)
    }

    @objc private func openYaziMenuAction() {
        toggleCompanionTool(.yazi)
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

        // Build action map: binding IDs → closures that execute the action.
        // This map is used by the key monitor to dispatch configurable bindings.

        // Helper: wrap an async WorkspaceManager operation into a fire-and-forget closure.
        func managerAction(_ action: @escaping (WorkspaceManager) async -> Void) -> (() -> Void) {
            { [weak self] in
                guard let manager = self?.workspaceManager else { return }
                Task { @MainActor in await action(manager) }
            }
        }

        keyMonitorActionMap = [
            "commandPalette.toggle": { [weak palette] in palette?.toggle() },
            "worktrees.create": { [weak self] in self?.showCreateWorktreePanel() },
            "worktrees.cycleNext": { [weak self] in self?.workspaceManager?.cycleWorktree(forward: true) },
            "worktrees.cyclePrevious": { [weak self] in self?.workspaceManager?.cycleWorktree(forward: false) },
            "quickJump.goto1": { [weak self] in self?.workspaceManager?.quickJump(index: 1) },
            "quickJump.goto2": { [weak self] in self?.workspaceManager?.quickJump(index: 2) },
            "quickJump.goto3": { [weak self] in self?.workspaceManager?.quickJump(index: 3) },
            "quickJump.goto4": { [weak self] in self?.workspaceManager?.quickJump(index: 4) },
            "quickJump.goto5": { [weak self] in self?.workspaceManager?.quickJump(index: 5) },
            "quickJump.goto6": { [weak self] in self?.workspaceManager?.quickJump(index: 6) },
            "quickJump.goto7": { [weak self] in self?.workspaceManager?.quickJump(index: 7) },
            "quickJump.goto8": { [weak self] in self?.workspaceManager?.quickJump(index: 8) },
            "quickJump.gotoLast": { [weak self] in self?.workspaceManager?.quickJump(index: 9) },
            "tabs.newTab": managerAction { await $0.createNewWindow() },
            "tabs.closeTab": managerAction { await $0.closeCurrentPane() },
            "tabs.nextTab": { [weak self] in self?.workspaceManager?.nextWindow() },
            "tabs.previousTab": { [weak self] in self?.workspaceManager?.previousWindow() },
            "panes.splitRight": managerAction { await $0.splitCurrentPane(horizontal: true) },
            "panes.splitDown": managerAction { await $0.splitCurrentPane(horizontal: false) },
            "panes.nextPane": managerAction { await $0.navigatePane(direction: .next) },
            "panes.previousPane": managerAction { await $0.navigatePane(direction: .previous) },
            "panes.navUp": managerAction { await $0.navigatePane(direction: .up) },
            "panes.navDown": managerAction { await $0.navigatePane(direction: .down) },
            "panes.navLeft": managerAction { await $0.navigatePane(direction: .left) },
            "panes.navRight": managerAction { await $0.navigatePane(direction: .right) },
            "panes.resizeUp": managerAction { await $0.resizePane(direction: .up) },
            "panes.resizeDown": managerAction { await $0.resizePane(direction: .down) },
            "panes.resizeLeft": managerAction { await $0.resizePane(direction: .left) },
            "panes.resizeRight": managerAction { await $0.resizePane(direction: .right) },
            "panes.equalize": managerAction { await $0.equalizePanes() },
            "panes.toggleZoom": managerAction { await $0.togglePaneZoom() },
            "tools.lazygit": { [weak self] in self?.toggleCompanionTool(.lazygit) },
            "tools.yazi": { [weak self] in self?.toggleCompanionTool(.yazi) },
            "window.toggleSidebar": { [weak self] in self?.rootSplitVC?.toggleSidebar() },
            "window.closeWindow": { [weak self] in self?.mainWindowController?.window?.close() },
            "settings.open": { [weak self] in self?.showSettingsWindow() },
            "settings.reload": { [weak self] in self?.terminalAreaController?.reloadConfig() },
            "other.openProject": { [weak self] in self?.showAddProjectPanel() },
            "other.agentDashboard": { [weak self] in self?.toggleAgentDashboardAction() },
            "other.projectSwitcher": { [weak self] in self?.commandPaletteController?.showProjectsOnly() },
        ]

        // Register key monitor that dispatches via the key binding store
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let store = self.keyBindingStore else { return event }

            // Pass through when the shortcut recorder is capturing input
            if MoriUI.isRecordingShortcut { return event }

            // Loop through configurable bindings and dispatch matching actions
            for binding in store.bindings where !binding.isLocked {
                guard let shortcut = binding.shortcut else { continue }
                if shortcut.matchesEvent(event) {
                    if let action = self.keyMonitorActionMap[binding.id] {
                        action()
                        return nil
                    }
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
            syncVisibleCompanionToolToSelection()

        case .worktree(let id, _, _, _):
            manager.selectWorktree(id)
            syncVisibleCompanionToolToSelection()

        case .window(let id, _, _, _):
            manager.selectWindow(id)
            syncVisibleCompanionToolToSelection()

        case .agent(let windowId, _, _, _):
            manager.selectWindow(windowId)
            syncVisibleCompanionToolToSelection()

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
        case "action.remote-connect":
            showRemoteConnectWizard()

        case "action.check-for-updates":
            updateController?.checkForUpdates()

        default:
            // Handle tool install hints — copy install command to clipboard
            if actionId.hasPrefix("action.tool-install-") {
                let toolId = String(actionId.dropFirst("action.tool-install-".count))
                if let tool = ToolDetector.knownTools.first(where: { $0.id == toolId }) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(tool.installHint, forType: .string)
                }
            }
            // Handle tool launch actions
            else if actionId.hasPrefix("action.tool-") {
                let toolId = String(actionId.dropFirst("action.tool-".count))
                if let tool = ToolDetector.detectAll().first(where: { $0.id == toolId }) {
                    Task { @MainActor in
                        await manager.launchToolInCurrentSession(
                            command: tool.command,
                            resolvedLocalCommand: tool.resolvedCommand,
                            windowName: tool.name.lowercased()
                        )
                    }
                }
            }
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

    private func startAutoReconnect() {
        reconnectTask?.cancel()
        guard let manager = workspaceManager,
              manager.hasSelectedWorktree else { return }
        terminalAreaController?.beginAutoReconnect()

        reconnectTask = Task { [weak self, weak manager] in
            guard let self, let manager else { return }

            let maxAttempts = 8
            for attempt in 0..<maxAttempts {
                if Task.isCancelled { return }
                let showErrors = (attempt == maxAttempts - 1)
                let ok = await manager.reconnectCurrentSession(showErrors: showErrors)
                if ok {
                    self.terminalAreaController?.endAutoReconnect()
                    self.reconnectTask = nil
                    return
                }

                let delaySeconds = min(1 << min(attempt, 3), 8)
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 500_000_000)
            }

            self.terminalAreaController?.endAutoReconnect()
            self.reconnectTask = nil
        }
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
        if model.droidEnabled {
            AgentHookConfigurator.installDroidHook()
        } else {
            AgentHookConfigurator.uninstallDroidHook()
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
    @State var proxySettings: ProxySettingsModel
    @State var toolSettings: ToolSettings
    let availableThemes: [String]
    let ghosttyDefaults: [String]
    var onChanged: (GhosttySettingsModel) -> Void
    var onOpenConfigFile: () -> Void
    var onAgentHookChanged: (AgentHookModel) -> Void
    var onProxyApply: (ProxySettingsModel) -> Void
    var onSystemProxyDetect: (() -> ProxySettingsModel)?
    var onToolSettingsChanged: (ToolSettings) -> Void

    // Key bindings
    @State var keyBindings: [KeyBinding]
    var keyBindingDefaults: [KeyBinding]
    var onKeyBindingValidate: ((KeyBinding) -> ConflictResult)?
    var onKeyBindingUpdate: ((KeyBinding) -> Void)?
    var onKeyBindingReset: ((String) -> Void)?
    var onKeyBindingResetAll: (() -> Void)?
    var keyBindingsRefresh: (() -> [KeyBinding])?

    init(
        initial: GhosttySettingsModel,
        availableThemes: [String],
        ghosttyDefaults: [String] = [],
        initialAgentHooks: AgentHookModel = AgentHookModel(),
        initialProxy: ProxySettingsModel = ProxySettingsModel(),
        initialTools: ToolSettings = ToolSettings(),
        onChanged: @escaping (GhosttySettingsModel) -> Void,
        onOpenConfigFile: @escaping () -> Void,
        onAgentHookChanged: @escaping (AgentHookModel) -> Void = { _ in },
        onProxyApply: @escaping (ProxySettingsModel) -> Void = { _ in },
        onSystemProxyDetect: (() -> ProxySettingsModel)? = nil,
        onToolSettingsChanged: @escaping (ToolSettings) -> Void = { _ in },
        keyBindings: [KeyBinding] = [],
        keyBindingDefaults: [KeyBinding] = [],
        onKeyBindingValidate: ((KeyBinding) -> ConflictResult)? = nil,
        onKeyBindingUpdate: ((KeyBinding) -> Void)? = nil,
        onKeyBindingReset: ((String) -> Void)? = nil,
        onKeyBindingResetAll: (() -> Void)? = nil,
        keyBindingsRefresh: (() -> [KeyBinding])? = nil
    ) {
        self._model = State(initialValue: initial)
        self._agentHooks = State(initialValue: initialAgentHooks)
        self._proxySettings = State(initialValue: initialProxy)
        self._toolSettings = State(initialValue: initialTools)
        self.availableThemes = availableThemes
        self.ghosttyDefaults = ghosttyDefaults
        self.onChanged = onChanged
        self.onOpenConfigFile = onOpenConfigFile
        self.onAgentHookChanged = onAgentHookChanged
        self.onProxyApply = onProxyApply
        self.onSystemProxyDetect = onSystemProxyDetect
        self.onToolSettingsChanged = onToolSettingsChanged
        self._keyBindings = State(initialValue: keyBindings)
        self.keyBindingDefaults = keyBindingDefaults
        self.onKeyBindingValidate = onKeyBindingValidate
        self.onKeyBindingUpdate = onKeyBindingUpdate
        self.onKeyBindingReset = onKeyBindingReset
        self.onKeyBindingResetAll = onKeyBindingResetAll
        self.keyBindingsRefresh = keyBindingsRefresh
    }

    var body: some View {
        GhosttySettingsView(
            model: $model,
            availableThemes: availableThemes,
            ghosttyDefaults: ghosttyDefaults,
            onChanged: { onChanged(model) },
            onOpenConfigFile: onOpenConfigFile,
            agentHooks: $agentHooks,
            onAgentHookChanged: onAgentHookChanged,
            proxySettings: $proxySettings,
            onProxyApply: onProxyApply,
            onSystemProxyDetect: onSystemProxyDetect,
            toolSettings: $toolSettings,
            onToolSettingsChanged: onToolSettingsChanged,
            keyBindings: keyBindings,
            keyBindingDefaults: keyBindingDefaults,
            onKeyBindingValidate: onKeyBindingValidate,
            onKeyBindingUpdate: { binding in
                onKeyBindingUpdate?(binding)
                if let refresh = keyBindingsRefresh { keyBindings = refresh() }
            },
            onKeyBindingReset: { id in
                onKeyBindingReset?(id)
                if let refresh = keyBindingsRefresh { keyBindings = refresh() }
            },
            onKeyBindingResetAll: {
                onKeyBindingResetAll?()
                if let refresh = keyBindingsRefresh { keyBindings = refresh() }
            }
        )
    }
}
