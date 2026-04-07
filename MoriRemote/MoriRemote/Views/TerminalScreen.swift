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
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(Theme.accent)
                        .scaleEffect(1.05)

                    Text(String(localized: "Opening shell…"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
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
