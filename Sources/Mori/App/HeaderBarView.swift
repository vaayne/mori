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

/// The center column's 38pt header: sidebar toggle + terminal tabs leading, a
/// drag-through gap, and a companion-pane toggle trailing, over a hairline bottom border.
@MainActor
final class HeaderBarView: TitleBarDragView, ThemedSurface {
    private static let normalLeadingInset: CGFloat = 14
    /// Clears the traffic lights when the sidebar is collapsed and they overlay this column.
    private static let collapsedLeadingInset: CGFloat = 78
    private static let buttonSize: CGFloat = 24
    private static let buttonTrailingMargin: CGFloat = 14
    private static let tabsButtonGap: CGFloat = 8

    private let tabsView: TerminalTabsBarView
    private let sidebarButton: NSButton
    private let toggleButton: NSButton
    private let hairline = NSView()
    private let onToggleSidebar: () -> Void
    private let onToggleCompanion: () -> Void
    private lazy var sidebarButtonLeadingConstraint = sidebarButton.leadingAnchor.constraint(
        equalTo: leadingAnchor, constant: Self.normalLeadingInset
    )

    var themedWindow: NSWindow? { nil }

    init(
        tabsView: TerminalTabsBarView,
        onToggleSidebar: @escaping () -> Void,
        onToggleCompanion: @escaping () -> Void
    ) {
        self.tabsView = tabsView
        self.onToggleSidebar = onToggleSidebar
        self.onToggleCompanion = onToggleCompanion
        let sidebarSymbol = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: .localized("Toggle Sidebar"))?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular))
        self.sidebarButton = NSButton(image: sidebarSymbol ?? NSImage(), target: nil, action: nil)
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

        for (button, action, label) in [
            (sidebarButton, #selector(toggleSidebar), String.localized("Toggle Sidebar (⌘B)")),
            (toggleButton, #selector(toggleCompanion), String.localized("Toggle Companion Pane")),
        ] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.isBordered = false
            button.bezelStyle = .regularSquare
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.contentTintColor = .secondaryLabelColor
            button.target = self
            button.action = action
            button.toolTip = label
            button.setAccessibilityLabel(label)
        }

        hairline.translatesAutoresizingMaskIntoConstraints = false
        hairline.wantsLayer = true

        addSubview(sidebarButton)
        addSubview(tabsView)
        addSubview(toggleButton)
        addSubview(hairline)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),

            sidebarButtonLeadingConstraint,
            sidebarButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            sidebarButton.widthAnchor.constraint(equalToConstant: Self.buttonSize),
            sidebarButton.heightAnchor.constraint(equalToConstant: Self.buttonSize),

            tabsView.leadingAnchor.constraint(equalTo: sidebarButton.trailingAnchor, constant: Self.tabsButtonGap),
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
        // Hand the tab strip the width between the leading controls and the trailing button
        // so it caps and shrinks its tabs within the header instead of growing under them.
        let leading = sidebarButtonLeadingConstraint.constant + Self.buttonSize + Self.tabsButtonGap
        let reserve = Self.buttonSize + Self.buttonTrailingMargin + Self.tabsButtonGap
        let available = bounds.width - leading - reserve
        tabsView.setStripWidth(max(available, 0))
    }

    /// Push the leading controls clear of the traffic lights when the sidebar collapses
    /// under them.
    func setSidebarCollapsed(_ collapsed: Bool) {
        let inset = collapsed ? Self.collapsedLeadingInset : Self.normalLeadingInset
        guard sidebarButtonLeadingConstraint.constant != inset else { return }
        sidebarButtonLeadingConstraint.constant = inset
        needsLayout = true
    }

    func applyTheme(_ themeInfo: GhosttyThemeInfo) {
        appearance = NSAppearance(named: themeInfo.isDark ? .darkAqua : .aqua)
        layer?.backgroundColor = themeInfo.effectiveBackground.cgColor
        // Approximates labelColor at low alpha; deterministic so split themes stay correct.
        let tint: NSColor = themeInfo.isDark ? .white : .black
        hairline.layer?.backgroundColor = tint.withAlphaComponent(0.06).cgColor
        sidebarButton.contentTintColor = .secondaryLabelColor
        toggleButton.contentTintColor = .secondaryLabelColor
    }

    @objc private func toggleSidebar() {
        onToggleSidebar()
    }

    @objc private func toggleCompanion() {
        onToggleCompanion()
    }
}
