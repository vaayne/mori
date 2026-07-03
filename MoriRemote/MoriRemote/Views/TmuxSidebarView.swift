#if os(iOS)
import SwiftUI

enum TmuxSidebarPresentation {
    case overlay
    case persistent

    var showsDismissButton: Bool { self == .overlay }
}

/// Sidebar wrapper that feeds coordinator state into the pure workspace list.
struct TmuxSidebarView: View {
    @Environment(ShellCoordinator.self) private var coordinator

    let presentation: TmuxSidebarPresentation
    let onDismiss: (() -> Void)?
    let onDisconnect: () -> Void
    let onSwitchHost: () -> Void

    @State private var renameTarget: TmuxSession?
    @State private var renameText = ""

    var body: some View {
        WorkspaceView(
            serverName: coordinator.activeServer?.displayName ?? String(localized: "Mori Remote"),
            sessions: coordinator.tmuxSessions,
            activeSessionName: coordinator.tmuxActiveSession?.name,
            activeWindowID: coordinator.tmuxActiveSession?.windows.first(where: { $0.isActive })?.id,
            showsDismissButton: presentation.showsDismissButton,
            onSelectWindow: { session, windowIndex in
                coordinator.selectTmuxWindow(session: session, windowIndex: windowIndex)
                onDismiss?()
            },
            onSelectPane: { session, windowIndex, paneId in
                coordinator.selectTmuxPane(session: session, windowIndex: windowIndex, paneId: paneId)
                onDismiss?()
            },
            onSwitchSession: { session in
                coordinator.switchTmuxSession(session)
                onDismiss?()
            },
            onRenameSession: { session in
                renameTarget = session
                renameText = session.name
            },
            onKillSession: { session in coordinator.closeTmuxSession(session) },
            onNewWindowAfter: { session, windowIndex in
                coordinator.newTmuxWindowAfter(session: session, windowIndex: windowIndex)
            },
            onCloseWindow: { session, windowIndex in
                coordinator.closeTmuxWindow(session: session, windowIndex: windowIndex)
            },
            onNewWindow: { coordinator.newTmuxWindow() },
            onNewSession: { coordinator.newTmuxSession() },
            onSwitchHost: onSwitchHost,
            onDisconnect: onDisconnect,
            onDismiss: onDismiss,
            onRefresh: { coordinator.refreshTmuxState() }
        )
        .alert(String(localized: "Rename Session"), isPresented: showRenameAlert) {
            TextField(String(localized: "Session name"), text: $renameText)
            Button(String(localized: "Cancel"), role: .cancel) { }
            Button(String(localized: "Rename")) {
                if let session = renameTarget, !renameText.isEmpty {
                    coordinator.renameTmuxSession(session.name, to: renameText)
                }
            }
        }
    }

    private var showRenameAlert: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }
}


enum TmuxAgentStatus: String, Sendable {
    case waiting
    case working
    case done

    init?(_ raw: String?) {
        guard let raw else { return nil }
        switch raw.lowercased() {
        case "waiting": self = .waiting
        case "working": self = .working
        case "done": self = .done
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .waiting: String(localized: "Needs input")
        case .working: String(localized: "Working")
        case .done: String(localized: "Done")
        }
    }

    var color: Color {
        switch self {
        case .waiting: Theme.agentWaiting
        case .working: Theme.agentWorking
        case .done: Theme.agentDone
        }
    }
}

struct WorkspaceProjectGroup: Identifiable, Sendable {
    let project: String
    let sessions: [TmuxSession]

    var id: String { project }
}

struct WorkspaceView: View {
    let serverName: String
    let sessions: [TmuxSession]
    let activeSessionName: String?
    let activeWindowID: String?
    let showsDismissButton: Bool
    let onSelectWindow: (String, Int) -> Void
    let onSelectPane: (String, Int, String) -> Void
    let onSwitchSession: (String) -> Void
    let onRenameSession: (TmuxSession) -> Void
    let onKillSession: (String) -> Void
    let onNewWindowAfter: (String, Int) -> Void
    let onCloseWindow: (String, Int) -> Void
    let onNewWindow: () -> Void
    let onNewSession: () -> Void
    let onSwitchHost: () -> Void
    let onDisconnect: () -> Void
    let onDismiss: (() -> Void)?
    let onRefresh: () -> Void

    private var projectGroups: [WorkspaceProjectGroup] {
        var order: [String] = []
        var map: [String: [TmuxSession]] = [:]
        for session in sessions {
            let project = Self.projectName(for: session.name)
            if map[project] == nil { order.append(project) }
            map[project, default: []].append(session)
        }
        return order.map { WorkspaceProjectGroup(project: $0, sessions: map[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceTopBar(
                serverName: serverName,
                showsDismissButton: showsDismissButton,
                onDismiss: onDismiss,
                onNewWindow: onNewWindow,
                onNewSession: onNewSession,
                onSwitchHost: onSwitchHost,
                onDisconnect: onDisconnect
            )

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if sessions.isEmpty {
                        WorkspaceEmptyState(onNewSession: onNewSession)
                    } else {
                        ForEach(projectGroups) { group in
                            WorkspaceProjectSection(
                                group: group,
                                activeSessionName: activeSessionName,
                                activeWindowID: activeWindowID,
                                onSelectWindow: onSelectWindow,
                                onSelectPane: onSelectPane,
                                onSwitchSession: onSwitchSession,
                                onRenameSession: onRenameSession,
                                onKillSession: onKillSession,
                                onNewWindowAfter: onNewWindowAfter,
                                onCloseWindow: onCloseWindow
                            )
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .refreshable { onRefresh() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.sidebarBg)
    }

    static func projectName(for sessionName: String) -> String {
        guard let slash = sessionName.firstIndex(of: "/") else { return sessionName }
        return String(sessionName[..<slash])
    }

    static func branchLabel(for sessionName: String) -> String? {
        guard let slash = sessionName.firstIndex(of: "/") else { return nil }
        let branch = sessionName[sessionName.index(after: slash)...]
        return branch.isEmpty ? nil : String(branch)
    }
}

private struct WorkspaceTopBar: View {
    let serverName: String
    let showsDismissButton: Bool
    let onDismiss: (() -> Void)?
    let onNewWindow: () -> Void
    let onNewSession: () -> Void
    let onSwitchHost: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if showsDismissButton {
                Button { onDismiss?() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }

            Circle()
                .fill(Theme.agentDone)
                .frame(width: 7, height: 7)

            Text(serverName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Menu {
                Button { onSwitchHost() } label: {
                    Label(String(localized: "Switch Host"), systemImage: "arrow.left.arrow.right")
                }
                Button(role: .destructive) { onDisconnect() } label: {
                    Label(String(localized: "Disconnect"), systemImage: "power")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 32)
            }

            Menu {
                Button { onNewWindow() } label: {
                    Label(String(localized: "New Window"), systemImage: "plus.rectangle")
                }
                Button { onNewSession() } label: {
                    Label(String(localized: "New Session"), systemImage: "plus.square.on.square")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.rowRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.rowRadius)
                            .strokeBorder(Theme.accentBorder, lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.sidebarBg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.divider).frame(height: 1)
        }
    }
}

private struct WorkspaceProjectSection: View {
    let group: WorkspaceProjectGroup
    let activeSessionName: String?
    let activeWindowID: String?
    let onSelectWindow: (String, Int) -> Void
    let onSelectPane: (String, Int, String) -> Void
    let onSwitchSession: (String) -> Void
    let onRenameSession: (TmuxSession) -> Void
    let onKillSession: (String) -> Void
    let onNewWindowAfter: (String, Int) -> Void
    let onCloseWindow: (String, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Text(group.project)
                    .moriSectionHeaderStyle()

                if showsAttachedInHeader {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 5, height: 5)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(group.sessions) { session in
                    WorkspaceSessionBlock(
                        session: session,
                        branchLabel: WorkspaceView.branchLabel(for: session.name),
                        isActiveSession: session.name == activeSessionName,
                        activeWindowID: activeWindowID,
                        hidesSessionHeader: hidesSessionHeader(for: session),
                        onSelectWindow: onSelectWindow,
                        onSelectPane: onSelectPane,
                        onSwitchSession: onSwitchSession,
                        onRenameSession: onRenameSession,
                        onKillSession: onKillSession,
                        onNewWindowAfter: onNewWindowAfter,
                        onCloseWindow: onCloseWindow
                    )
                }
            }
        }
    }

    private var showsAttachedInHeader: Bool {
        group.sessions.count == 1 && WorkspaceView.branchLabel(for: group.sessions[0].name) == nil && group.sessions[0].isAttached
    }

    private func hidesSessionHeader(for session: TmuxSession) -> Bool {
        group.sessions.count == 1 && WorkspaceView.branchLabel(for: session.name) == nil
    }
}

private struct WorkspaceSessionBlock: View {
    let session: TmuxSession
    let branchLabel: String?
    let isActiveSession: Bool
    let activeWindowID: String?
    let hidesSessionHeader: Bool
    let onSelectWindow: (String, Int) -> Void
    let onSelectPane: (String, Int, String) -> Void
    let onSwitchSession: (String) -> Void
    let onRenameSession: (TmuxSession) -> Void
    let onKillSession: (String) -> Void
    let onNewWindowAfter: (String, Int) -> Void
    let onCloseWindow: (String, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !hidesSessionHeader {
                sessionHeader
            }

            VStack(spacing: 2) {
                ForEach(session.windows) { window in
                    let isSelected = isActiveSession && window.id == activeWindowID
                    WorkspaceWindowRow(
                        window: window,
                        isSelected: isSelected,
                        onSelect: { onSelectWindow(session.name, window.index) },
                        onNewAfter: { onNewWindowAfter(session.name, window.index) },
                        onClose: { onCloseWindow(session.name, window.index) }
                    )

                    if window.panes.count > 1 {
                        VStack(spacing: 2) {
                            ForEach(window.panes) { pane in
                                WorkspacePaneRow(
                                    pane: pane,
                                    isSelected: isSelected && pane.isActive,
                                    onSelect: { onSelectPane(session.name, window.index, pane.paneId) }
                                )
                            }
                        }
                        .padding(.leading, 28)
                    }
                }
            }
        }
    }

    private var sessionHeader: some View {
        HStack(spacing: 7) {
            Text(branchLabel ?? session.name)
                .font(.system(size: 12, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(isActiveSession ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)

            if session.isAttached {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 5, height: 5)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button { onSwitchSession(session.name) } label: {
                Label(String(localized: "Switch to Session"), systemImage: "arrow.right.square")
            }

            Divider()

            Button { onRenameSession(session) } label: {
                Label(String(localized: "Rename Session"), systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) { onKillSession(session.name) } label: {
                Label(String(localized: "Kill Session"), systemImage: "xmark.circle")
            }
        }
    }
}

private struct WorkspaceWindowRow: View {
    let window: TmuxWindow
    let isSelected: Bool
    let onSelect: () -> Void
    let onNewAfter: () -> Void
    let onClose: () -> Void

    private var title: String {
        window.workspaceTitle
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "rectangle.inset.filled" : "rectangle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Theme.rowTitleFont)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)

                    if !window.shortPath.isEmpty {
                        Text(window.shortPath)
                            .font(Theme.monoCaptionFont)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                AgentStatusChip(status: window.agentStatus, fallback: window.fallbackCommand)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(isSelected ? Theme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: Theme.rowRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { onSelect() } label: {
                Label(String(localized: "Switch to Window"), systemImage: "arrow.up.right.square")
            }

            Divider()

            Button { onNewAfter() } label: {
                Label(String(localized: "New Window After"), systemImage: "plus.rectangle")
            }

            Divider()

            Button(role: .destructive) { onClose() } label: {
                Label(String(localized: "Close Window"), systemImage: "xmark.circle")
            }
        }
    }
}

private struct WorkspacePaneRow: View {
    let pane: TmuxPane
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: pane.isActive ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(pane.displayLabel)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)

                    if !pane.shortPath.isEmpty {
                        Text(pane.shortPath)
                            .font(Theme.monoCaptionFont)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                AgentStatusChip(status: TmuxAgentStatus(pane.agentState), fallback: pane.command)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? Theme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: Theme.rowRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct AgentStatusChip: View {
    let status: TmuxAgentStatus?
    let fallback: String?
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(chipColor)
                .frame(width: 6, height: 6)
                .opacity(status == .working && pulse ? 0.35 : 1)

            Text(label)
                .font(Theme.chipFont)
                .foregroundStyle(chipColor)
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.chipHorizontalPadding)
        .padding(.vertical, Theme.chipVerticalPadding)
        .background(chipColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(chipColor.opacity(0.24), lineWidth: 1)
        )
        .onAppear { updatePulse(for: status) }
        .onChange(of: status) { _, newStatus in
            updatePulse(for: newStatus)
        }
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

    private var label: String {
        if let status { return status.title }
        let value = fallback?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? String(localized: "tmux") : value
    }

    private var chipColor: Color {
        status?.color ?? Theme.textTertiary
    }
}

private struct WorkspaceEmptyState: View {
    let onNewSession: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)

            Text(String(localized: "No tmux sessions"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Text(String(localized: "Start tmux to manage\nwindows from here."))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            Button(action: onNewSession) {
                Label(String(localized: "New Session"), systemImage: "plus")
            }
            .buttonStyle(Theme.SecondaryButtonStyle(
                foreground: Theme.accent,
                background: Theme.accentSoft,
                border: Theme.accentBorder
            ))
            .frame(maxWidth: 180)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }
}

extension TmuxPane {
    var shortPath: String {
        guard !path.isEmpty else { return "" }
        let display = path.contains("/Users/") || path.contains("/home/")
            ? "~" + path.split(separator: "/").dropFirst(2).map { "/" + $0 }.joined()
            : path
        let parts = display.split(separator: "/")
        if parts.count <= 2 { return display }
        return "…/" + parts.suffix(2).joined(separator: "/")
    }
}

extension TmuxWindow {
    var workspaceTitle: String {
        let pane = panes.first(where: { $0.agentName?.isEmpty == false }) ?? panes.first
        if let agentName = pane?.agentName, !agentName.isEmpty { return agentName }
        if !name.isEmpty && name != "[tmux]" { return name }
        if let command = fallbackCommand, !command.isEmpty { return command }
        return name
    }

    var agentStatus: TmuxAgentStatus? {
        let statuses = panes.compactMap { TmuxAgentStatus($0.agentState) }
        if statuses.contains(.waiting) { return .waiting }
        if statuses.contains(.working) { return .working }
        if statuses.contains(.done) { return .done }
        return nil
    }

    var fallbackCommand: String? {
        panes.first(where: { !$0.command.isEmpty })?.command
    }
}
#endif
