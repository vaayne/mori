import MoriTerminal
import SwiftUI

struct TerminalScreen: View {
    @Environment(ShellCoordinator.self) private var coordinator

    let serverName: String
    let onDisconnect: () -> Void

    @State private var shellStarted = false
    @State private var showToolbar = false
    @State private var showKeyBarCustomize = false
    @State private var renderer: SwiftTermRendererBox?
    @State private var accessoryBar = TerminalAccessoryBar()

    var body: some View {
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
            .ignoresSafeArea(edges: .bottom)

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

            if showToolbar {
                toolbarOverlay
            }
        }
        .overlay(alignment: .topTrailing) {
            if coordinator.state == .shell && !showToolbar {
                menuButton
            }
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

    // MARK: - Menu Button

    private var menuButton: some View {
        Button {
            withAnimation(.spring(duration: 0.25)) { showToolbar = true }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .padding(.trailing, 12)
        .padding(.top, 8)
    }

    // MARK: - Toolbar Overlay

    private func dismissToolbar() {
        withAnimation(.spring(duration: 0.25)) { showToolbar = false }
        renderer?.value.activateKeyboard()
    }

    private var toolbarOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { dismissToolbar() }

            VStack {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)

                        Text(serverName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)

                        Spacer()

                        Button { dismissToolbar() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Theme.textTertiary)
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.08), in: Circle())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    Divider().overlay(Theme.cardBorder)

                    Button {
                        dismissToolbar()
                        onDisconnect()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 13, weight: .medium))
                            Text("Disconnect")
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(Theme.destructive)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                }
                .background(.ultraThinMaterial)

                Spacer()
            }
        }
        .transition(.opacity)
    }
}

@MainActor
private final class SwiftTermRendererBox {
    let value: SwiftTermRenderer
    init(_ value: SwiftTermRenderer) { self.value = value }
}
