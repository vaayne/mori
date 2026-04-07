import MoriTerminal
import SwiftUI

struct TerminalScreen: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(ShellCoordinator.self) private var coordinator

    let sessionHost: TerminalSessionHost
    let serverName: String
    let onDisconnect: () -> Void
    let onSwitchHost: () -> Void

    @State private var showSidebar = false

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
        .onAppear {
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

            if newState != .shell {
                showSidebar = false
            }
        }
        .onChange(of: horizontalSizeClass) { _, newSizeClass in
            if newSizeClass == .regular {
                showSidebar = false
            }
        }
    }

    private var compactWorkspace: some View {
        SidebarContainer(isOpen: $showSidebar) {
            sidebarContent(presentation: .overlay, onDismiss: { showSidebar = false })
        } content: {
            terminalContent(showsCompactChrome: true)
        }
    }

    private var regularWorkspace: some View {
        HStack(spacing: 0) {
            sidebarContent(presentation: .persistent, onDismiss: nil)
                .frame(width: 304)
                .background(Theme.sidebarBg)

            Rectangle()
                .fill(Theme.divider)
                .frame(width: 1)

            terminalContent(showsCompactChrome: false)
        }
        .background(Theme.terminalBg.ignoresSafeArea())
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

    private func terminalContent(showsCompactChrome: Bool) -> some View {
        ZStack(alignment: .topLeading) {
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

            if showsCompactChrome && coordinator.state == .shell {
                compactTopBar
                    .padding(.top, 8)
                    .padding(.leading, 12)
            }
        }
    }

    private var compactTopBar: some View {
        HStack(spacing: 10) {
            Button {
                showSidebar = true
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(serverName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Text(coordinator.activeServer?.subtitle ?? "")
                    .font(Theme.monoCaptionFont)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.trailing, 12)
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
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
