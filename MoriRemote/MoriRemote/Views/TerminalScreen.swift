import SwiftUI

struct TerminalScreen: View {
    @Environment(SpikeCoordinator.self) private var coordinator

    let sessionName: String
    let serverName: String
    let onDisconnect: () -> Void

    @State private var attachStarted = false
    @State private var showStatusBar = false

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

            // Top status bar (swipe down to reveal)
            if showStatusBar {
                statusBarOverlay
            }
        }
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.height > 40 && abs(value.translation.width) < 60 {
                        withAnimation(.spring(duration: 0.3)) { showStatusBar = true }
                    }
                }
        )
        .statusBarHidden(!showStatusBar)
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

    // MARK: - Status Bar

    private var statusBarOverlay: some View {
        VStack {
            HStack(spacing: 12) {
                // Connection indicator
                Circle()
                    .fill(coordinator.isTerminalAttached ? Color.green : Color.yellow)
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

                Button {
                    onDisconnect()
                } label: {
                    Text("Disconnect")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.destructive)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.destructive.opacity(0.15), in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            Spacer()
        }
        .onTapGesture {
            withAnimation(.spring(duration: 0.3)) { showStatusBar = false }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

extension SpikeCoordinator {
    var isTerminalAttached: Bool {
        if case .attached = state { return true }
        return false
    }
}
