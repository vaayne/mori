import SwiftUI
import MoriRemoteProtocol

/// Floating button overlaid on the terminal view to toggle between
/// read-only and interactive modes.
struct ModeToggleButton: View {
    let mode: SessionMode
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: mode == .readOnly ? "eye" : "keyboard")
                    .font(.system(size: 14, weight: .medium))
                Text(mode == .readOnly ? "Read-Only" : "Interactive")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(mode == .readOnly ? .orange : .green)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        }
        .animation(.easeInOut(duration: 0.2), value: mode)
    }
}
