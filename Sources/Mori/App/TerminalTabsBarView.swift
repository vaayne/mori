import AppKit
import Observation
import MoriCore
import MoriUI

/// Native AppKit terminal tabs for the window titlebar toolbar.
///
/// This intentionally avoids SwiftUI hosting inside `NSToolbarItem`: the toolbar's
/// flexible-space layout has repeatedly rendered hosted SwiftUI as a blank strip.
@MainActor
final class TerminalTabsBarView: NSView {
    private static let tabWidth: CGFloat = 160
    private static let tabHeight: CGFloat = 24
    private static let plusWidth: CGFloat = 26
    private static let horizontalPadding = MoriTokens.Spacing.sm
    private static let spacing = MoriTokens.Spacing.xs

    private let appState: AppState
    private let onSelectWindow: (String) -> Void
    private let onCloseWindow: (String) -> Void
    private let onCreateWindow: () -> Void
    private let stackView = NSStackView()
    private lazy var widthConstraint = widthAnchor.constraint(equalToConstant: contentWidth)
    private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: TerminalTabsBarView.tabHeight)

    private var contentWidth: CGFloat = TerminalTabsBarView.horizontalPadding * 2 + TerminalTabsBarView.plusWidth
    private var stripWidth: CGFloat = TerminalTabsBarView.horizontalPadding * 2 + TerminalTabsBarView.plusWidth
    var onIntrinsicContentSizeChanged: (() -> Void)?

    init(
        appState: AppState,
        onSelectWindow: @escaping (String) -> Void,
        onCloseWindow: @escaping (String) -> Void,
        onCreateWindow: @escaping () -> Void
    ) {
        self.appState = appState
        self.onSelectWindow = onSelectWindow
        self.onCloseWindow = onCloseWindow
        self.onCreateWindow = onCreateWindow
        super.init(frame: .zero)
        setupView()
        updateAndObserve()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil(max(stripWidth, contentWidth)), height: Self.tabHeight)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        stackView.arrangedSubviews.forEach { $0.needsDisplay = true }
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
        NSLayoutConstraint.activate([widthConstraint, heightConstraint])

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fill
        stackView.spacing = Self.spacing
        stackView.edgeInsets = NSEdgeInsets(
            top: 0,
            left: Self.horizontalPadding,
            bottom: 0,
            right: Self.horizontalPadding
        )
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func updateAndObserve() {
        withObservationTracking {
            rebuildTabs(
                windows: appState.windowsForSelectedWorktree,
                selectedWindowId: appState.uiState.selectedWindowId
            )
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateAndObserve()
            }
        }
    }

    private func rebuildTabs(windows: [RuntimeWindow], selectedWindowId: String?) {
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for window in windows {
            let tab = TerminalTabControl(
                window: window,
                isSelected: window.tmuxWindowId == selectedWindowId,
                onSelect: onSelectWindow,
                onClose: onCloseWindow
            )
            stackView.addArrangedSubview(tab)
        }

        let addButton = TerminalIconButton(
            symbolName: "plus",
            size: NSSize(width: Self.plusWidth, height: Self.tabHeight),
            cornerRadius: MoriTokens.Radius.small,
            pointSize: 12,
            weight: .semibold,
            accessibilityLabel: String.localized("New Tab"),
            onPress: onCreateWindow
        )
        stackView.addArrangedSubview(addButton)

        let slackSpacer = NSView()
        slackSpacer.translatesAutoresizingMaskIntoConstraints = false
        slackSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        slackSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let slackWidth = slackSpacer.widthAnchor.constraint(equalToConstant: 10_000)
        slackWidth.priority = .defaultLow
        NSLayoutConstraint.activate([
            slackWidth,
            slackSpacer.heightAnchor.constraint(equalToConstant: Self.tabHeight),
        ])
        stackView.addArrangedSubview(slackSpacer)

        let itemCount = windows.count + 1
        contentWidth = Self.horizontalPadding * 2
            + CGFloat(windows.count) * Self.tabWidth
            + Self.plusWidth
            + CGFloat(max(0, itemCount)) * Self.spacing
        syncStripWidth()
    }

    func setStripWidth(_ width: CGFloat) {
        let width = ceil(max(width, contentWidth))
        guard abs(width - stripWidth) > 0.5 else { return }
        stripWidth = width
        syncStripWidth()
    }

    private func syncStripWidth() {
        widthConstraint.constant = max(stripWidth, contentWidth)
        heightConstraint.constant = Self.tabHeight
        invalidateIntrinsicContentSize()
        needsLayout = true
        onIntrinsicContentSizeChanged?()
    }
}

@MainActor
private final class TerminalTabControl: NSControl {
    private static let width: CGFloat = 160
    private static let height: CGFloat = 24

    private let runtimeWindow: RuntimeWindow
    private let selected: Bool
    private let onSelect: (String) -> Void
    private let onClose: (String) -> Void
    private let closeButton: TerminalIconButton

    init(
        window: RuntimeWindow,
        isSelected: Bool,
        onSelect: @escaping (String) -> Void,
        onClose: @escaping (String) -> Void
    ) {
        self.runtimeWindow = window
        self.selected = isSelected
        self.onSelect = onSelect
        self.onClose = onClose
        self.closeButton = TerminalIconButton(
            symbolName: "xmark",
            size: NSSize(width: 16, height: 16),
            cornerRadius: 8,
            pointSize: 10,
            weight: .bold,
            accessibilityLabel: String.localized("Close Tab"),
            onPress: { onClose(window.tmuxWindowId) }
        )
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.height))
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.width),
            heightAnchor.constraint(equalToConstant: Self.height),
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
        addSubview(closeButton)
        closeButton.isHidden = !isSelected
        toolTip = tabTitle(for: window)
        setAccessibilityRole(.button)
        setAccessibilityLabel(tabTitle(for: window))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.width, height: Self.height)
    }

    override func layout() {
        super.layout()
        closeButton.frame = NSRect(x: bounds.maxX - MoriTokens.Spacing.md - 16, y: (bounds.height - 16) / 2, width: 16, height: 16)
    }

    override func mouseDown(with event: NSEvent) {
        onSelect(runtimeWindow.tmuxWindowId)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let pillRect = bounds
        let path = NSBezierPath(roundedRect: pillRect, xRadius: MoriTokens.Radius.medium, yRadius: MoriTokens.Radius.medium)
        NSColor.labelColor.withAlphaComponent(selected ? 0.11 : 0.055).setFill()
        path.fill()

        if selected {
            let strokePath = NSBezierPath(roundedRect: pillRect.insetBy(dx: 0.5, dy: 0.5), xRadius: MoriTokens.Radius.medium, yRadius: MoriTokens.Radius.medium)
            strokePath.lineWidth = 1
            NSColor.labelColor.withAlphaComponent(0.16).setStroke()
            strokePath.stroke()
        }

        drawDot()
        drawTitle()
    }

    private func drawDot() {
        let dotSize = MoriTokens.Icon.dot
        let rect = NSRect(
            x: MoriTokens.Spacing.md,
            y: (bounds.height - dotSize) / 2,
            width: dotSize,
            height: dotSize
        )
        tabDotColor(for: runtimeWindow, isSelected: selected).setFill()
        NSBezierPath(ovalIn: rect).fill()
    }

    private func drawTitle() {
        let font = NSFont.systemFont(ofSize: 13, weight: selected ? .semibold : .medium)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: selected ? NSColor.labelColor : NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle,
        ]
        let attributedTitle = NSAttributedString(string: tabTitle(for: runtimeWindow), attributes: attributes)
        let closeWidth = selected ? 16 + MoriTokens.Spacing.sm : 0
        let textX = MoriTokens.Spacing.md + MoriTokens.Icon.dot + MoriTokens.Spacing.md
        let textRect = NSRect(
            x: textX,
            y: (bounds.height - font.ascender + font.descender) / 2 - 1,
            width: bounds.width - textX - MoriTokens.Spacing.md - closeWidth,
            height: bounds.height
        )
        attributedTitle.draw(in: textRect)
    }

    private func tabTitle(for window: RuntimeWindow) -> String {
        if !window.title.isEmpty {
            return window.title
        }
        return String.localized("Window \(window.tmuxWindowIndex)")
    }

    private func tabDotColor(for window: RuntimeWindow, isSelected: Bool) -> NSColor {
        if isSelected { return .controlAccentColor }
        if window.detectedAgent != nil || window.agentState != .none { return .systemBlue }
        if window.hasUnreadOutput { return .systemYellow }
        switch window.tag {
        case .server: return .systemGreen
        case .agent: return .systemBlue
        default: return .systemGray
        }
    }
}

@MainActor
private final class TerminalIconButton: NSButton {
    private let fixedSize: NSSize
    private let cornerRadius: CGFloat
    private let onPress: () -> Void

    init(
        symbolName: String,
        size: NSSize,
        cornerRadius: CGFloat,
        pointSize: CGFloat,
        weight: NSFont.Weight,
        accessibilityLabel: String,
        onPress: @escaping () -> Void
    ) {
        self.fixedSize = size
        self.cornerRadius = cornerRadius
        self.onPress = onPress
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)) ?? NSImage()
        super.init(frame: NSRect(origin: .zero, size: size))
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size.width),
            heightAnchor.constraint(equalToConstant: size.height),
        ])
        self.image = image
        self.imagePosition = .imageOnly
        self.imageScaling = .scaleProportionallyDown
        self.isBordered = false
        self.bezelStyle = .regularSquare
        self.target = self
        self.action = #selector(press)
        self.contentTintColor = .secondaryLabelColor
        self.setAccessibilityLabel(accessibilityLabel)
        self.toolTip = accessibilityLabel
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize { fixedSize }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(MoriTokens.Opacity.quiet).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        super.draw(dirtyRect)
    }

    @objc private func press() {
        onPress()
    }
}
