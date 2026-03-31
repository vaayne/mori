#if os(iOS)
import SwiftTerm
import UIKit

/// Customizable horizontal key bar — bottom row of the terminal accessory.
///
/// Renders a scrollable row of key buttons matching the design mockup.
/// Keys are grouped with thin divider separators.
@MainActor
final class KeyBarView: UIView {

    weak var terminalView: SwiftTerm.TerminalView?

    /// Called when the user taps the gear button to customize the key bar.
    var onCustomizeTapped: (() -> Void)?

    /// Called when a tmux action is selected from the popup menu.
    var onTmuxAction: ((TmuxCommand) -> Void)?

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var keyButtons: [UIView] = []

    /// Current layout. Setting this rebuilds the bar.
    var layout: [KeyAction] = KeyBarLayout.load() {
        didSet { rebuildKeys() }
    }

    /// Tracks ctrl toggle state for visual feedback.
    private var ctrlActive = false

    // MARK: - Auto-repeat

    private var repeatAction: KeyAction?
    private var repeatTask: Task<Void, Never>?
    private var repeatTimer: Timer?

    // MARK: - Colors (matching design tokens)

    private let keyBg = UIColor(red: 0.165, green: 0.165, blue: 0.196, alpha: 1)       // #2a2a32
    private let keySpecialBg = UIColor(red: 0.118, green: 0.118, blue: 0.149, alpha: 1) // #1e1e26
    private let keyActiveBg = UIColor(red: 0.30, green: 0.85, blue: 0.75, alpha: 0.15)
    private let accentColor = UIColor(red: 0.30, green: 0.85, blue: 0.75, alpha: 1)     // teal
    private let textColor = UIColor.white
    private let textDim = UIColor.white.withAlphaComponent(0.55)
    private let dividerColor = UIColor.white.withAlphaComponent(0.06)
    private let tmuxKeyBg = UIColor(red: 0.30, green: 0.85, blue: 0.75, alpha: 0.08)
    private let tmuxBorder = UIColor(red: 0.30, green: 0.85, blue: 0.75, alpha: 0.15)

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Right-edge fade gradient to hint that the bar scrolls.
    private let fadeView = UIView()
    private let fadeGradient = CAGradientLayer()

    private func setup() {
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.delegate = self
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        stackView.axis = .horizontal
        stackView.spacing = 3
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        // Right-edge fade hint
        fadeView.isUserInteractionEnabled = false
        fadeView.translatesAutoresizingMaskIntoConstraints = false
        let barBg = UIColor(red: 0.102, green: 0.102, blue: 0.125, alpha: 1)
        fadeGradient.colors = [barBg.withAlphaComponent(0).cgColor, barBg.cgColor]
        fadeGradient.startPoint = CGPoint(x: 0, y: 0.5)
        fadeGradient.endPoint = CGPoint(x: 1, y: 0.5)
        fadeView.layer.addSublayer(fadeGradient)
        addSubview(fadeView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 4),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -4),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),

            fadeView.trailingAnchor.constraint(equalTo: trailingAnchor),
            fadeView.topAnchor.constraint(equalTo: topAnchor),
            fadeView.bottomAnchor.constraint(equalTo: bottomAnchor),
            fadeView.widthAnchor.constraint(equalToConstant: 28),
        ])

        // Listen for ctrl state changes from SwiftTerm
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(ctrlModifierReset),
            name: .terminalViewControlModifierReset,
            object: nil
        )

        rebuildKeys()
    }

    @objc private func ctrlModifierReset() {
        ctrlActive = false
        updateCtrlButton()
    }

    // MARK: - Build Keys

    private func rebuildKeys() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        keyButtons = []

        // Tmux menu button — first in bar
        let tmux = makeTmuxMenuButton()
        stackView.addArrangedSubview(tmux)
        keyButtons.append(tmux)

        // Divider after tmux button
        let div0 = makeDivider()
        stackView.addArrangedSubview(div0)
        keyButtons.append(div0)

        for action in layout {
            if action == .divider {
                let div = makeDivider()
                stackView.addArrangedSubview(div)
                keyButtons.append(div)
            } else if action.isTmux {
                // Skip individual tmux keys — they're in the popup now
                continue
            } else {
                let btn = makeKeyButton(for: action)
                stackView.addArrangedSubview(btn)
                keyButtons.append(btn)
            }
        }

        // Gear button at the end for customization
        let gear = makeGearButton()
        stackView.addArrangedSubview(gear)
        keyButtons.append(gear)
    }

    private func makeDivider() -> UIView {
        let v = UIView()
        v.backgroundColor = dividerColor
        v.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: 1),
            v.heightAnchor.constraint(equalToConstant: 22),
        ])
        return v
    }

    private func makeKeyButton(for action: KeyAction) -> UIButton {
        let btn = UIButton(type: .system)
        btn.tag = action.hashValue
        btn.layer.cornerRadius = 6
        btn.clipsToBounds = true

        // Sizing — compact to fit more keys on screen
        let isArrow = action.iconName != nil
        let minW: CGFloat = isArrow ? 28 : 32
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
        NSLayoutConstraint.activate([
            btn.heightAnchor.constraint(equalToConstant: 30),
            btn.widthAnchor.constraint(greaterThanOrEqualToConstant: minW),
        ])

        // Content
        if let iconName = action.iconName {
            let config = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            let img = UIImage(systemName: iconName, withConfiguration: config)
            btn.setImage(img, for: .normal)
            btn.tintColor = textColor
        } else {
            btn.setTitle(action.label, for: .normal)
            btn.titleLabel?.font = action.isSpecial || action.isTmux
                ? .systemFont(ofSize: 11, weight: .semibold)
                : .systemFont(ofSize: 12, weight: .medium)
        }

        // Colors
        applyStyle(to: btn, action: action, active: false)

        // Store action as associated object
        objc_setAssociatedObject(btn, &KeyBarView.actionKey, action, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        // Actions
        btn.addTarget(self, action: #selector(keyDown(_:)), for: .touchDown)
        btn.addTarget(self, action: #selector(keyUp(_:)), for: .touchUpInside)
        btn.addTarget(self, action: #selector(keyUp(_:)), for: .touchUpOutside)
        btn.addTarget(self, action: #selector(keyUp(_:)), for: .touchCancel)

        return btn
    }

    private func applyStyle(to btn: UIButton, action: KeyAction, active: Bool) {
        if action.isTmux {
            btn.backgroundColor = active ? accentColor.withAlphaComponent(0.2) : tmuxKeyBg
            btn.setTitleColor(accentColor, for: .normal)
            btn.layer.borderWidth = 1
            btn.layer.borderColor = tmuxBorder.cgColor
        } else if action.isSpecial {
            btn.backgroundColor = active ? keyActiveBg : keySpecialBg
            btn.setTitleColor(active ? accentColor : textDim, for: .normal)
        } else {
            btn.backgroundColor = active ? keyActiveBg : keyBg
            btn.setTitleColor(textColor, for: .normal)
        }
    }

    private static var actionKey: UInt8 = 0

    private func action(for button: UIButton) -> KeyAction? {
        objc_getAssociatedObject(button, &KeyBarView.actionKey) as? KeyAction
    }

    private var tmuxMenuButton: UIButton?

    private func makeTmuxMenuButton() -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle("tmux", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 11, weight: .bold)
        btn.setTitleColor(accentColor, for: .normal)
        btn.backgroundColor = tmuxKeyBg
        btn.layer.cornerRadius = 6
        btn.layer.borderWidth = 1
        btn.layer.borderColor = tmuxBorder.cgColor
        btn.clipsToBounds = true
        btn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        btn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            btn.heightAnchor.constraint(equalToConstant: 30),
        ])

        btn.menu = buildTmuxMenu()
        btn.showsMenuAsPrimaryAction = true
        tmuxMenuButton = btn
        return btn
    }

    private func buildTmuxMenu() -> UIMenu {
        let items: [(TmuxCommand, String, String)] = [
            (.newWindow,        "New Tab",         "plus.square"),
            (.nextWindow,       "Next Tab",        "arrow.right.square"),
            (.prevWindow,       "Previous Tab",    "arrow.left.square"),
            (.splitRight,       "Split Right",     "rectangle.split.2x1"),
            (.splitDown,        "Split Down",      "rectangle.split.1x2"),
            (.nextPane,         "Next Pane",       "arrow.right.circle"),
            (.prevPane,         "Previous Pane",   "arrow.left.circle"),
            (.toggleZoom,       "Toggle Zoom",     "arrow.up.left.and.arrow.down.right"),
            (.closePane,        "Close Pane",      "xmark.square"),
            (.detach,           "Detach",          "eject"),
        ]

        let actions = items.map { cmd, title, icon in
            UIAction(title: title, image: UIImage(systemName: icon)) { [weak self] _ in
                self?.onTmuxAction?(cmd)
            }
        }

        return UIMenu(title: "", children: actions)
    }

    private func makeGearButton() -> UIButton {
        let btn = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let img = UIImage(systemName: "gearshape", withConfiguration: config)
        btn.setImage(img, for: .normal)
        btn.tintColor = textDim
        btn.backgroundColor = keySpecialBg
        btn.layer.cornerRadius = 6
        btn.clipsToBounds = true
        btn.addTarget(self, action: #selector(gearTapped), for: .touchUpInside)
        btn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            btn.heightAnchor.constraint(equalToConstant: 32),
            btn.widthAnchor.constraint(equalToConstant: 32),
        ])
        return btn
    }

    @objc private func gearTapped() {
        onCustomizeTapped?()
    }

    // MARK: - Key Events

    @objc private func keyDown(_ sender: UIButton) {
        guard let action = action(for: sender) else { return }
        UIDevice.current.playInputClick()

        if action.supportsAutoRepeat {
            startAutoRepeat(action)
        } else {
            executeAction(action, button: sender)
        }
    }

    @objc private func keyUp(_ sender: UIButton) {
        cancelAutoRepeat()
    }

    private func executeAction(_ action: KeyAction, button: UIButton? = nil) {
        guard let tv = terminalView else { return }
        let handled = action.execute(on: tv)
        if !handled && action == .ctrl {
            ctrlActive = tv.controlModifier
            updateCtrlButton()
        }
    }

    private func updateCtrlButton() {
        for view in stackView.arrangedSubviews {
            guard let btn = view as? UIButton,
                  let action = action(for: btn),
                  action == .ctrl
            else { continue }
            applyStyle(to: btn, action: action, active: ctrlActive)
        }
    }

    // MARK: - Auto-repeat

    private func startAutoRepeat(_ action: KeyAction) {
        cancelAutoRepeat()
        repeatAction = action
        executeAction(action)

        repeatTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms initial delay
            guard !Task.isCancelled else { return }
            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.executeAction(action)
                }
            }
        }
    }

    private func cancelAutoRepeat() {
        repeatTask?.cancel()
        repeatTask = nil
        repeatTimer?.invalidate()
        repeatTimer = nil
        repeatAction = nil
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        fadeGradient.frame = fadeView.bounds
        updateFadeVisibility()
    }

    private func updateFadeVisibility() {
        let maxOffset = scrollView.contentSize.width - scrollView.bounds.width
        fadeView.isHidden = maxOffset <= 0 || scrollView.contentOffset.x >= maxOffset - 4
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 44)
    }
}

// MARK: - UIScrollViewDelegate

extension KeyBarView: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateFadeVisibility()
    }
}
#endif
