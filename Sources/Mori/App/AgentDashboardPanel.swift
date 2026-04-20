import AppKit
import SwiftUI
import MoriCore
import MoriTerminal
import MoriUI

/// Floating NSPanel hosting the multi-pane agent dashboard.
/// Non-modal, utility window style, toggleable independently of the main window.
@MainActor
final class AgentDashboardPanel: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var refreshTimer: Timer?
    private weak var workspaceManager: WorkspaceManager?
    private let paneOutputCache: PaneOutputCache
    private let tilesModel = MultiPaneDashboardView.Model()
    private let chromePaletteStore = MoriChromePaletteStore()
    private var chromePalette: MoriChromePalette = .fallback
    private var currentAppearance: NSAppearance?

    init(workspaceManager: WorkspaceManager, paneOutputCache: PaneOutputCache) {
        self.workspaceManager = workspaceManager
        self.paneOutputCache = paneOutputCache
    }

    /// Sync panel appearance with the Ghostty terminal theme.
    func updateAppearance(themeInfo: GhosttyThemeInfo, chromePalette: MoriChromePalette) {
        self.chromePalette = chromePalette
        chromePaletteStore.palette = chromePalette
        let appearance = NSAppearance(named: themeInfo.isDark ? .darkAqua : .aqua)
        currentAppearance = appearance
        guard let panel else { return }
        panel.appearance = appearance
        panel.backgroundColor = chromePalette.panelBackground.nsColor
        panel.contentView?.layer?.backgroundColor = chromePalette.panelBackground.nsColor.cgColor
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        if panel == nil {
            createPanel()
        }
        panel?.orderFrontRegardless()
        startRefresh()
    }

    func hide() {
        panel?.orderOut(nil)
        stopRefresh()
    }

    // MARK: - Panel Creation

    private func createPanel() {
        let contentRect = NSRect(x: 0, y: 0, width: 800, height: 500)
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable, .utilityWindow]
        let panel = NSPanel(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        panel.title = String.localized("Agent Dashboard")
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.center()
        panel.minSize = NSSize(width: 400, height: 300)
        panel.isOpaque = true
        panel.backgroundColor = chromePalette.panelBackground.nsColor
        panel.appearance = currentAppearance

        let view = MultiPaneDashboardView(model: self.tilesModel)
        let hostingView = NSHostingView(rootView: view.environmentObject(chromePaletteStore))
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        // Use a wrapper view so auto layout anchors the hosting view to fill the panel
        let wrapper = NSView(frame: contentRect)
        wrapper.wantsLayer = true
        wrapper.layer?.backgroundColor = chromePalette.panelBackground.nsColor.cgColor
        wrapper.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: wrapper.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
        ])
        panel.contentView = wrapper
        self.panel = panel
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        stopRefresh()
    }

    // MARK: - Refresh

    private func startRefresh() {
        stopRefresh()
        // Initial refresh
        Task { await refreshTiles() }
        // Periodic refresh every 5 seconds
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.isVisible else {
                    self.stopRefresh()
                    return
                }
                await self.refreshTiles()
            }
        }
    }

    private func stopRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func refreshTiles() async {
        guard let manager = workspaceManager else { return }

        let agentWindows = manager.appState.runtimeWindows.filter {
            $0.detectedAgent != nil || $0.agentState != .none
        }

        var newTiles: [MultiPaneDashboardView.TileData] = []
        for window in agentWindows {
            let worktree = manager.appState.worktrees.first(where: { $0.id == window.worktreeId })
            let project = worktree.flatMap { wt in manager.appState.projects.first(where: { $0.id == wt.projectId }) }
            let paneId = window.activePaneId ?? window.tmuxWindowId
            var output = paneOutputCache.get(paneId) ?? ""

            if output.isEmpty {
                // Fetch fresh output
                if let worktree {
                    let tmux = manager.tmuxBackendForWorktree(worktree)
                    let rawId = manager.rawTmuxWindowId(from: window)
                    let targetPaneId = window.activePaneId ?? rawId
                    if let captured = try? await tmux.capturePaneOutput(paneId: targetPaneId, lineCount: 50) {
                        output = captured
                        paneOutputCache.set(paneId, output: captured)
                    }
                }
            }

            newTiles.append(MultiPaneDashboardView.TileData(
                id: window.tmuxWindowId,
                agentName: window.detectedAgent ?? "agent",
                windowTitle: window.title,
                projectName: project?.name ?? "",
                worktreeName: worktree?.name ?? "",
                agentState: window.agentState,
                output: output
            ))
        }

        tilesModel.tiles = newTiles
    }
}
