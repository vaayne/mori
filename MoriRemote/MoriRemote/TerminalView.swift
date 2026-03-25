import SwiftUI
import GhosttyKit

/// SwiftUI wrapper around the ghostty UIView surface.
struct TerminalView: View {
    var body: some View {
        GhosttyTerminalRepresentable()
            .ignoresSafeArea()
    }
}

private struct GhosttyTerminalRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        guard let app = GhosttyAppContext.shared.app else {
            let label = UILabel()
            label.text = "ghostty app not initialized"
            label.textColor = .red
            label.textAlignment = .center
            return label
        }

        let surfaceView = GhosttySurfaceUIView(app: app)
        return surfaceView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
