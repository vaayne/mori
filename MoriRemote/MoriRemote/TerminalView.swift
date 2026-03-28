import MoriTerminal
import SwiftUI
import UIKit

struct TerminalView: UIViewRepresentable {
    let onRendererReady: @MainActor (GhosttyiOSRenderer) -> Void
    let onRendererResize: @MainActor (GhosttyiOSRenderer) -> Void

    func makeUIView(context: Context) -> TerminalContainerView {
        let view = TerminalContainerView()
        view.onRendererReady = onRendererReady
        view.onRendererResize = onRendererResize
        view.notifyRendererReady()
        return view
    }

    func updateUIView(_ uiView: TerminalContainerView, context: Context) {
        uiView.onRendererReady = onRendererReady
        uiView.onRendererResize = onRendererResize
        uiView.notifyRendererReady()
    }
}

@MainActor
final class TerminalContainerView: UIView {
    let renderer = GhosttyiOSRenderer(frame: .zero)

    var onRendererReady: (@MainActor (GhosttyiOSRenderer) -> Void)?
    var onRendererResize: (@MainActor (GhosttyiOSRenderer) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        renderer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(renderer)
        NSLayoutConstraint.activate([
            renderer.topAnchor.constraint(equalTo: topAnchor),
            renderer.leadingAnchor.constraint(equalTo: leadingAnchor),
            renderer.trailingAnchor.constraint(equalTo: trailingAnchor),
            renderer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onRendererResize?(renderer)
    }

    func notifyRendererReady() {
        onRendererReady?(renderer)
    }
}
