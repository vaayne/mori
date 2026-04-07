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
            terminalContent(showsSidebarButton: true)
        }
    }

    private var regularWorkspace: some View {
        HStack(spacing: 0) {
            sidebarContent(presentation: .persistent, onDismiss: nil)
                .frame(width: 320)
                .background(Color(red: 0.07, green: 0.07, blue: 0.10))

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1)

            terminalContent(showsSidebarButton: false)
        }
        .background(Color.black.ignoresSafeArea())
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

    private func terminalContent(showsSidebarButton: Bool) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TerminalView(
                onRendererReady: { renderer in
                    sessionHost.handleRendererReady(renderer, coordinator: coordinator)
                }
            )
            .ignoresSafeArea(.container, edges: .bottom)

            if coordinator.state != .shell {
                VStack(spacing: 14) {
                    ProgressView()
                        .tint(Theme.accent)
                        .scaleEffect(1.2)

                    Text("Opening shell…")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .overlay(alignment: .topLeading) {
            if showsSidebarButton && coordinator.state == .shell && !showSidebar {
                sidebarButton
            }
        }
    }

    private var sidebarButton: some View {
        Button {
            showSidebar = true
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .padding(.leading, 12)
        .padding(.top, 8)
    }
}
