import MoriTerminal
import SwiftUI

struct TerminalScreen: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(ShellCoordinator.self) private var coordinator

    let sessionHost: TerminalSessionHost
    let serverName: String
    let onDisconnect: () -> Void
    let onSwitchHost: () -> Void
    let onBackToWorkspace: () -> Void

    @State private var showRegularSidebar = true

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularWorkspace
            } else {
                compactWorkspace
            }
        }
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .sheet(isPresented: keyBarCustomizeBinding) {
            KeyBarCustomizeView(keyBar: sessionHost.accessoryBar.keyBar)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            String(localized: "Tmux Shortcuts"),
            isPresented: tmuxCommandsBinding,
            titleVisibility: .visible
        ) {
            Button(String(localized: "New Tab")) { coordinator.handleTmuxCommand(.newWindow) }
            Button(String(localized: "Next Tab")) { coordinator.handleTmuxCommand(.nextWindow) }
            Button(String(localized: "Previous Tab")) { coordinator.handleTmuxCommand(.prevWindow) }
            Button(String(localized: "Split Right")) { coordinator.handleTmuxCommand(.splitRight) }
            Button(String(localized: "Split Down")) { coordinator.handleTmuxCommand(.splitDown) }
            Button(String(localized: "Next Pane")) { coordinator.handleTmuxCommand(.nextPane) }
            Button(String(localized: "Previous Pane")) { coordinator.handleTmuxCommand(.prevPane) }
            Button(String(localized: "Toggle Zoom")) { coordinator.handleTmuxCommand(.toggleZoom) }
            Button(String(localized: "Close Pane"), role: .destructive) { coordinator.handleTmuxCommand(.closePane) }
            Button(String(localized: "Detach"), role: .destructive) { coordinator.handleTmuxCommand(.detach) }
            Button(String(localized: "Cancel"), role: .cancel) { }
        }
        .onAppear {
            sessionHost.accessoryBar.onBackTapped = onSwitchHost
            sessionHost.handleCoordinatorStateChange(
                coordinator.state,
                activeServerID: coordinator.activeServer?.id
            )
        }
        .onChange(of: coordinator.state) { _, newState in
            sessionHost.handleCoordinatorStateChange(
                newState,
                activeServerID: coordinator.activeServer?.id
            )
        }
        .onChange(of: horizontalSizeClass) { _, newSizeClass in
            sessionHost.accessoryBar.onBackTapped = onSwitchHost
            if newSizeClass == .regular {
                sessionHost.showSidebar = false
            }
        }
    }

    private var compactWorkspace: some View {
        VStack(spacing: 0) {
            compactTopBar
            if compactWindows.count > 1 {
                compactWindowChipsBar
            }
            terminalContent(showsCompactChrome: true)
        }
        .background(Theme.terminalBg.ignoresSafeArea())
        .sheet(isPresented: sidebarBinding) {
            sidebarContent(presentation: .overlay, onDismiss: { sessionHost.showSidebar = false })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.sidebarBg)
        }
    }

    private var regularWorkspace: some View {
        HStack(spacing: 0) {
            if showRegularSidebar {
                sidebarContent(
                    presentation: .persistent,
                    onDismiss: { showRegularSidebar = false }
                )
                .frame(width: 304)
                .background(Theme.sidebarBg)

                Rectangle()
                    .fill(Theme.divider)
                    .frame(width: 1)
            }

            terminalContent(showsCompactChrome: false)
        }
        .safeAreaInset(edge: .top, alignment: .leading) {
            if coordinator.state == .shell && !showRegularSidebar {
                HStack {
                    regularSidebarRevealButton
                    Spacer(minLength: 0)
                }
                .padding(.top, 6)
                .padding(.leading, 12)
                .padding(.trailing, 12)
            }
        }
        .background(Theme.terminalBg.ignoresSafeArea())
    }

    private var compactTopBar: some View {
        HStack(spacing: 10) {
            Button(action: onBackToWorkspace) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Button { sessionHost.showSidebar = true } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(currentWindow?.workspaceTitle ?? String(localized: "Terminal"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)

                    Text(coordinator.tmuxActiveSession?.name ?? serverName)
                        .font(Theme.monoCaptionFont)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            if let window = currentWindow {
                AgentStatusChip(status: window.agentStatus, fallback: window.fallbackCommand)
            }

            Button { sessionHost.showTmuxCommands = true } label: {
                Image(systemName: "command")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 44)
        .padding(.horizontal, 8)
        .background(Theme.terminalBg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.divider).frame(height: 1)
        }
    }

    private var compactWindowChipsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(compactWindows) { window in
                    TerminalWindowChip(
                        window: window,
                        isSelected: window.isActive,
                        onSelect: {
                            coordinator.selectTmuxWindow(session: window.sessionName, windowIndex: window.index)
                        }
                    )
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
        }
        .background(Theme.terminalBg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.divider).frame(height: 1)
        }
    }

    private var compactWindows: [TmuxWindow] {
        coordinator.tmuxActiveSession?.windows ?? []
    }

    private var currentWindow: TmuxWindow? {
        coordinator.tmuxActiveSession?.windows.first(where: { $0.isActive })
    }

    private func sidebarContent(
        presentation: TmuxSidebarPresentation,
        onDismiss: (() -> Void)?
    ) -> some View {
        TmuxSidebarView(
            presentation: presentation,
            onDismiss: onDismiss,
            onDisconnect: onDisconnect,
            onSwitchHost: onSwitchHost
        )
    }

    private var keyBarCustomizeBinding: Binding<Bool> {
        Binding(
            get: { sessionHost.showKeyBarCustomize },
            set: { sessionHost.showKeyBarCustomize = $0 }
        )
    }

    private var tmuxCommandsBinding: Binding<Bool> {
        Binding(
            get: { sessionHost.showTmuxCommands },
            set: { sessionHost.showTmuxCommands = $0 }
        )
    }

    private var sidebarBinding: Binding<Bool> {
        Binding(
            get: { sessionHost.showSidebar },
            set: { sessionHost.showSidebar = $0 }
        )
    }

    private func terminalContent(showsCompactChrome: Bool) -> some View {
        ZStack {
            Theme.terminalBg.ignoresSafeArea()

            TerminalView(
                onRendererReady: { renderer in
                    sessionHost.handleRendererReady(renderer, coordinator: coordinator)
                }
            )
            .ignoresSafeArea(.container, edges: .bottom)

            if coordinator.state != .shell {
                TerminalPreparingOverlay(
                    serverName: serverName,
                    subtitle: coordinator.activeServer?.subtitle ?? "",
                    sessionName: coordinator.activeServer?.defaultSession ?? ""
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }

    private var regularSidebarRevealButton: some View {
        Button {
            showRegularSidebar = true
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct TerminalWindowChip: View {
    let window: TmuxWindow
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var pulse = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 5) {
                Circle()
                    .fill(chipColor)
                    .frame(width: 5, height: 5)
                    .opacity(window.agentStatus == .working && pulse ? 0.35 : 1)

                Text(window.workspaceTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(isSelected ? Theme.accentSoft : Theme.mutedSurface, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Theme.accentBorder : Theme.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onAppear { updatePulse(for: window.agentStatus) }
        .onChange(of: window.agentStatus) { _, newStatus in
            updatePulse(for: newStatus)
        }
    }

    private var chipColor: Color {
        window.agentStatus?.color ?? Theme.textTertiary
    }

    private func updatePulse(for status: TmuxAgentStatus?) {
        if status == .working {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                pulse = false
            }
        }
    }
}

private struct TerminalPreparingOverlay: View {
    let serverName: String
    let subtitle: String
    let sessionName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .fill(Theme.accentSoft)
                    .frame(width: 42, height: 42)
                    .overlay {
                        ProgressView()
                            .tint(Theme.accent)
                    }

                VStack(alignment: .leading, spacing: 6) {
                    TerminalStateBadge(title: String(localized: "SSH Connected"))

                    Text(String(localized: "Preparing Terminal"))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Text(serverName)
                        .font(Theme.rowTitleFont)
                        .foregroundStyle(Theme.textSecondary)

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Theme.monoDetailFont)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            VStack(spacing: 0) {
                terminalMetadataRow(label: String(localized: "Session"), value: sessionName, monospace: true)
                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 1)
                terminalMetadataRow(label: String(localized: "Status"), value: String(localized: "Opening shell…"))
            }
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )

            Text(String(localized: "Opening the interactive shell and checking tmux windows."))
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: 360, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .padding(.horizontal, 24)
    }

    private func terminalMetadataRow(label: String, value: String, monospace: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            Spacer(minLength: 8)

            Text(value)
                .font(monospace ? Theme.monoDetailFont : .system(size: 13))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct TerminalStateBadge: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 6, height: 6)

            Text(title)
                .font(Theme.shortcutFont.weight(.semibold))
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.accentBorder, lineWidth: 1)
        )
    }
}
