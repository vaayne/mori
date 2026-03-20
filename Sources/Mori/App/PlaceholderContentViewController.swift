import AppKit

/// Placeholder content view controller displayed when no worktree is selected.
/// Will be replaced by TerminalAreaViewController in Phase 4.
final class PlaceholderContentViewController: NSViewController {

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true

        let label = NSTextField(labelWithString: .localized("Select a worktree"))
        label.font = .systemFont(ofSize: 18, weight: .light)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        self.view = container
    }
}
