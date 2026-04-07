import MoriTerminal
import SwiftUI

struct TerminalScreen: View {
    @Environment(ShellCoordinator.self) private var coordinator

    let serverName: String
    let onDisconnect: () -> Void

    @State private var shellStarted = false
    @State private var showKeyBarCustomize = false
    @State private var renderer: SwiftTermRendererBox?
    @State private var accessoryBar = TerminalAccessoryBar()
    @State private var showSidebar = false

    var body: some View {
        SidebarContainer(isOpen: $showSidebar) {
            TmuxSidebarView(
                onDismiss: { showSidebar = false },
                onDisconnect: onDisconnect,
                onSwitchHost: onDisconnect
            )
        } content: {
            terminalContent
        }
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showKeyBarCustomize) {
            KeyBarCustomizeView(keyBar: accessoryBar.keyBar)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: coordinator.state) { _, newState in
            if newState == .shell {
                renderer?.value.activateKeyboard()
            }
        }
    }

    // MARK: - Terminal Content

    private var terminalContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TerminalView(
                onRendererReady: { r in
                    renderer = SwiftTermRendererBox(r)

                    guard !shellStarted else { return }

                    r.initialLayoutHandler = { [weak r] cols, rows in
                        guard let r else { return }
                        startShellOnce(renderer: r)
                    }

                    let size = r.gridSize()
                    if size.cols > 0 && size.rows > 0 {
                        startShellOnce(renderer: r)
                    }
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
            if coordinator.state == .shell && !showSidebar {
                sidebarButton
            }
        }
    }

    private func startShellOnce(renderer r: SwiftTermRenderer) {
        guard !shellStarted else { return }
        shellStarted = true
        coordinator.accessoryBar = accessoryBar
        accessoryBar.onCustomizeTapped = {
            showKeyBarCustomize = true
        }
        Task {
            await coordinator.openShell(renderer: r)
        }
    }

    // MARK: - Sidebar Button

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

@MainActor
private final class SwiftTermRendererBox {
    let value: SwiftTermRenderer
    init(_ value: SwiftTermRenderer) { self.value = value }
}
