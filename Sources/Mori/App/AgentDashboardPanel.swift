import AppKit
import SwiftUI
import MoriCore
import MoriUI

/// Floating NSPanel hosting the multi-pane agent dashboard.
/// Non-modal, utility window style, toggleable independently of the main window.
@MainActor
final class AgentDashboardPanel {
    private var panel: NSPanel?
    private var refreshTimer: Timer?
    private weak var workspaceManager: WorkspaceManager?
    private let paneOutputCache: PaneOutputCache

    /// Observable tiles data for the SwiftUI dashboard view.
    private var tiles: [MultiPaneDashboardView.TileData] = []

    init(workspaceManager: WorkspaceManager, paneOutputCache: PaneOutputCache) {
        self.workspaceManager = workspaceManager
        self.paneOutputCache = paneOutputCache
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
            defer: true
        )
        panel.title = String.localized("Agent Dashboard")
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.center()

        updatePanelContent(panel: panel)
        self.panel = panel
    }

    private func updatePanelContent(panel: NSPanel) {
        let view = MultiPaneDashboardView(tiles: tiles)
        let hostingView = NSHostingView(rootView: view)
        panel.contentView = hostingView
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
            let paneId = window.activePaneId ?? window.tmuxWindowId
            var output = paneOutputCache.get(paneId) ?? ""

            if output.isEmpty {
                // Fetch fresh output
                if let worktree = manager.appState.worktrees.first(where: { $0.id == window.worktreeId }) {
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
                agentState: window.agentState,
                output: output
            ))
        }

        tiles = newTiles
        if let panel {
            updatePanelContent(panel: panel)
        }
    }
}
