import MoriTerminal
import SwiftUI
import UIKit

struct TerminalView: UIViewRepresentable {
    let onRendererReady: @MainActor (SwiftTermRenderer) -> Void

    func makeUIView(context: Context) -> SwiftTermRenderer {
        let renderer = SwiftTermRenderer()
        // Defer callback so SwiftUI layout is settled before the coordinator acts.
        // Don't activate keyboard here — let openShell do it after the accessory bar is wired.
        DispatchQueue.main.async {
            onRendererReady(renderer)
        }
        return renderer
    }

    func updateUIView(_ uiView: SwiftTermRenderer, context: Context) {
        // No-op — renderer is long-lived, coordinator holds a weak ref.
    }
}
