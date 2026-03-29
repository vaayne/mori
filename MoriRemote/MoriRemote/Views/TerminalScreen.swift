import SwiftUI

struct TerminalScreen: View {
    @Environment(SpikeCoordinator.self) private var coordinator

    let sessionName: String
    let serverName: String
    let onDetach: () -> Void
    let onDisconnect: () -> Void

    @State private var attachStarted = false
    @State private var showToolbar = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TerminalView(
                onRendererReady: { renderer in
                    coordinator.registerRenderer(renderer)

                    guard !attachStarted else { return }
                    attachStarted = true

                    Task {
                        await coordinator.attachSession(name: sessionName, renderer: renderer)
                    }
                }
            )
            .ignoresSafeArea(edges: .bottom)

            // Attach overlay
            if coordinator.isAttachingSession || !coordinator.isTerminalAttached {
                attachingOverlay
            }

            // Floating menu button (top-right)
            if coordinator.isTerminalAttached {
                floatingMenuButton
            }

            // Toolbar overlay
            if showToolbar {
                toolbarOverlay
            }
        }
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
    }

    // MARK: - Attaching Overlay

    private var attachingOverlay: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(Theme.accent)
                .scaleEffect(1.2)

            Text("Attaching session…")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Floating Menu Button

    private var floatingMenuButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    withAnimation(.spring(duration: 0.25)) { showToolbar.toggle() }
                } label: {
                    Image(systemName: showToolbar ? "xmark" : "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 32, height: 32)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(.trailing, 12)
                .padding(.top, 8)
            }
            Spacer()
        }
    }

    // MARK: - Toolbar Overlay

    private var toolbarOverlay: some View {
        VStack {
            // Top bar
            VStack(spacing: 0) {
                // Session info
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(serverName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("session: \(sessionName)")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider().overlay(Theme.cardBorder)

                // Actions
                HStack(spacing: 0) {
                    toolbarAction("Sessions", icon: "rectangle.stack", color: Theme.accent) {
                        withAnimation(.spring(duration: 0.25)) { showToolbar = false }
                        onDetach()
                    }

                    Divider().overlay(Theme.cardBorder).frame(height: 36)

                    toolbarAction("Disconnect", icon: "xmark.circle", color: Theme.destructive) {
                        withAnimation(.spring(duration: 0.25)) { showToolbar = false }
                        onDisconnect()
                    }
                }
                .padding(.vertical, 6)
            }
            .background(.ultraThinMaterial)

            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .onTapGesture {
            withAnimation(.spring(duration: 0.25)) { showToolbar = false }
        }
    }

    private func toolbarAction(_ label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(label)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
    }
}

extension SpikeCoordinator {
    var isTerminalAttached: Bool {
        if case .attached = state { return true }
        return false
    }
}
