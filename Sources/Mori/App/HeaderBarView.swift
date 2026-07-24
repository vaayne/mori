import AppKit
import MoriTerminal
import MoriUI

/// A title-bar-height strip that acts as the window's drag surface.
///
/// With `.fullSizeContentView` the app owns window movement in the regions that used
/// to be AppKit's titlebar. Empty chrome forwards a plain drag to the window and a
/// double-click to the standard title action the user picked in System Settings.
/// Interactive subviews (buttons, tabs) get the mouse-down first via hit-testing and
/// consume it, so only clicks that land on bare chrome reach here.
@MainActor
class TitleBarDragView: NSView {
    static let height: CGFloat = 38

    // Route the mouse-down to us (not the window server) so the double-click branch
    // below can honour the user's title-action preference; the window server ignores it.
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            Self.performTitleAction(for: window)
            return
        }
        window?.performDrag(with: event)
    }

    /// Perform the title-bar double-click action from System Settings > Desktop & Dock.
    static func performTitleAction(for window: NSWindow?) {
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": window?.performMiniaturize(nil)
        case "None": break
        default: window?.performZoom(nil) // "Maximize"/"Fill" and the unset default all zoom
        }
    }
}

/// The center column's 38pt header: terminal tabs leading, a drag-through gap, and a
/// single companion-pane toggle trailing, over a hairline bottom border.
@MainActor
final class HeaderBarView: TitleBarDragView, ThemedSurface {
    private static let normalLeadingInset: CGFloat = 14
    /// Clears the traffic lights when the sidebar is collapsed and they overlay this column.
    private static let collapsedLeadingInset: CGFloat = 78
    private static let buttonSize: CGFloat = 24
    private static let buttonTrailingMargin: CGFloat = 14
    private static let tabsButtonGap: CGFloat = 8

    private let tabsView: TerminalTabsBarView
    private let toggleButton: NSButton
    private let hairline = NSView()
    private let onToggleCompanion: () -> Void
    private lazy var tabsLeadingConstraint = tabsView.leadingAnchor.constraint(
        equalTo: leadingAnchor, constant: Self.normalLeadingInset
    )

    var themedWindow: NSWindow? { nil }

    init(tabsView: TerminalTabsBarView, onToggleCompanion: @escaping () -> Void) {
        self.tabsView = tabsView
        self.onToggleCompanion = onToggleCompanion
        let symbol = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: .localized("Toggle Companion Pane"))?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular))
        self.toggleButton = NSButton(image: symbol ?? NSImage(), target: nil, action: nil)
        super.init(frame: .zero)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        wantsLayer = true

        toggleButton.translatesAutoresizingMaskIntoConstraints = false
        toggleButton.isBordered = false
        toggleButton.bezelStyle = .regularSquare
        toggleButton.imagePosition = .imageOnly
        toggleButton.imageScaling = .scaleProportionallyDown
        toggleButton.contentTintColor = .secondaryLabelColor
        toggleButton.target = self
        toggleButton.action = #selector(toggleCompanion)
        toggleButton.toolTip = .localized("Toggle Companion Pane")
        toggleButton.setAccessibilityLabel(.localized("Toggle Companion Pane"))

        hairline.translatesAutoresizingMaskIntoConstraints = false
        hairline.wantsLayer = true

        addSubview(tabsView)
        addSubview(toggleButton)
        addSubview(hairline)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),

            tabsLeadingConstraint,
            tabsView.centerYAnchor.constraint(equalTo: centerYAnchor),

            toggleButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.buttonTrailingMargin),
            toggleButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            toggleButton.widthAnchor.constraint(equalToConstant: Self.buttonSize),
            toggleButton.heightAnchor.constraint(equalToConstant: Self.buttonSize),

            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    override func layout() {
        super.layout()
        // Hand the tab strip the width between its leading inset and the trailing button
        // so it caps and shrinks its tabs within the header instead of growing under them.
        let reserve = Self.buttonSize + Self.buttonTrailingMargin + Self.tabsButtonGap
        let available = bounds.width - tabsLeadingConstraint.constant - reserve
        tabsView.setStripWidth(max(available, 0))
    }

    /// Push the tabs clear of the traffic lights when the sidebar collapses under them.
    func setSidebarCollapsed(_ collapsed: Bool) {
        let inset = collapsed ? Self.collapsedLeadingInset : Self.normalLeadingInset
        guard tabsLeadingConstraint.constant != inset else { return }
        tabsLeadingConstraint.constant = inset
        needsLayout = true
    }

    func applyTheme(_ themeInfo: GhosttyThemeInfo) {
        appearance = NSAppearance(named: themeInfo.isDark ? .darkAqua : .aqua)
        layer?.backgroundColor = themeInfo.effectiveBackground.cgColor
        // Approximates labelColor at low alpha; deterministic so split themes stay correct.
        let tint: NSColor = themeInfo.isDark ? .white : .black
        hairline.layer?.backgroundColor = tint.withAlphaComponent(0.06).cgColor
        toggleButton.contentTintColor = .secondaryLabelColor
    }

    @objc private func toggleCompanion() {
        onToggleCompanion()
    }
}
