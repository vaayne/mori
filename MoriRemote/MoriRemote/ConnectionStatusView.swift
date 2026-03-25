import SwiftUI

/// Small overlay showing the current connection state.
/// Visible when not connected (disconnected, connecting, reconnecting).
/// Hides automatically when connected to avoid obscuring the terminal.
struct ConnectionStatusView: View {
    let status: ConnectionStatus

    var body: some View {
        if status != .connected {
            HStack(spacing: 8) {
                statusIndicator
                Text(statusText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.75))
            .clipShape(Capsule())
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch status {
        case .disconnected:
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
        case .connecting, .reconnecting:
            ProgressView()
                .tint(.white)
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)
        case .connected:
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
        }
    }

    private var statusText: String {
        switch status {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting..."
        case .connected: "Connected"
        case .reconnecting: "Reconnecting..."
        }
    }
}
