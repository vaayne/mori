#if os(iOS)
import SwiftTerm
import UIKit

/// Customizable horizontal key bar for terminal accessory actions.
@MainActor
final class KeyBarView: UIView {

    weak var terminalView: SwiftTerm.TerminalView?
    var onBackTapped: (() -> Void)?
    var onCustomizeTapped: (() -> Void)?
    var onTmuxMenuTapped: (() -> Void)?
    var onTmuxAction: ((TmuxCommand) -> Void)?

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var keyButtons: [UIView] = []

    var layout: [KeyAction] = KeyBarLayout.load() {
        didSet { rebuildKeys() }
    }

    private var ctrlActive = false
    private var repeatAction: KeyAction?
    private var repeatTask: Task<Void, Never>?
    private var repeatTimer: Timer?

    private let barBg = UIColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1)
    private let keyBg = UIColor.white.withAlphaComponent(0.05)
    private let keySpecialBg = UIColor.white.withAlphaComponent(0.035)
    private let keyActiveBg = UIColor.tintColor.withAlphaComponent(0.16)
    private let accentColor = UIColor.tintColor
    private let textColor = UIColor.white.withAlphaComponent(0.96)
    private let textDim = UIColor.white.withAlphaComponent(0.62)
    private let dividerColor = UIColor.white.withAlphaComponent(0.08)
    private let tmuxKeyBg = UIColor.tintColor.withAlphaComponent(0.12)
    private let tmuxBorder = UIColor.tintColor.withAlphaComponent(0.28)
    private let keyBorder = UIColor.white.withAlphaComponent(0.08)

    private let fadeView = UIView()
    private let fadeGradient = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        MainActor.assumeIsolated {
            cancelAutoRepeat()
            NotificationCenter.default.removeObserver(self)
        }
    }

    private func setup() {
        backgroundColor = barBg

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.delaysContentTouches = false
        scrollView.delegate = self
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        stackView.axis = .horizontal
        stackView.spacing = 4
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        fadeView.isUserInteractionEnabled = false
        fadeView.translatesAutoresizingMaskIntoConstraints = false
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
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 6),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -6),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),

            fadeView.trailingAnchor.constraint(equalTo: trailingAnchor),
            fadeView.topAnchor.constraint(equalTo: topAnchor),
            fadeView.bottomAnchor.constraint(equalTo: bottomAnchor),
            fadeView.widthAnchor.constraint(equalToConstant: 28),
        ])

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

    private func rebuildKeys() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        keyButtons = []

        let back = makeBackButton()
        stackView.addArrangedSubview(back)
        keyButtons.append(back)

        let divBack = makeDivider()
        stackView.addArrangedSubview(divBack)
        keyButtons.append(divBack)

        let tmux = makeTmuxMenuButton()
        stackView.addArrangedSubview(tmux)
        keyButtons.append(tmux)

        let div0 = makeDivider()
        stackView.addArrangedSubview(div0)
        keyButtons.append(div0)

        for action in layout {
            if action == .divider {
                let div = makeDivider()
                stackView.addArrangedSubview(div)
                keyButtons.append(div)
            } else if action.isTmux {
                continue
            } else {
                let btn = makeKeyButton(for: action)
                stackView.addArrangedSubview(btn)
                keyButtons.append(btn)
            }
        }

        let divEnd = makeDivider()
        stackView.addArrangedSubview(divEnd)
        keyButtons.append(divEnd)

        let keyboardButton = makeKeyboardDismissButton()
        stackView.addArrangedSubview(keyboardButton)
        keyButtons.append(keyboardButton)

        let gear = makeGearButton()
        stackView.addArrangedSubview(gear)
        keyButtons.append(gear)
    }

    private func makeDivider() -> UIView {
        let view = UIView()
        view.backgroundColor = dividerColor
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 1),
            view.heightAnchor.constraint(equalToConstant: 20),
        ])
        return view
    }

    private func makeKeyButton(for action: KeyAction) -> UIButton {
        let button = UIButton(type: .system)
        button.tag = action.hashValue
        button.layer.cornerRadius = 7
        button.layer.borderWidth = 1
        button.layer.borderColor = keyBorder.cgColor
        button.clipsToBounds = true
        button.adjustsImageWhenHighlighted = false
        button.isExclusiveTouch = true

        let isArrow = action.iconName != nil
        let minWidth: CGFloat = isArrow ? 28 : 34
        button.translatesAutoresizingMaskIntoConstraints = false
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 7, bottom: 0, right: 7)
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 30),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth),
        ])

        if let iconName = action.iconName {
            let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            button.setImage(UIImage(systemName: iconName, withConfiguration: config), for: .normal)
            button.tintColor = textColor
        } else {
            button.setTitle(action.label, for: .normal)
            button.titleLabel?.font = action.isSpecial || action.isTmux
                ? .monospacedSystemFont(ofSize: 10, weight: .semibold)
                : .monospacedSystemFont(ofSize: 11, weight: .medium)
        }

        applyStyle(to: button, action: action, active: false)
        objc_setAssociatedObject(button, &KeyBarView.actionKey, action, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        button.addTarget(self, action: #selector(keyDown(_:)), for: .touchDown)
        button.addTarget(self, action: #selector(keyUp(_:)), for: .touchUpInside)
        button.addTarget(self, action: #selector(keyUp(_:)), for: .touchUpOutside)
        button.addTarget(self, action: #selector(keyUp(_:)), for: .touchCancel)

        return button
    }

    private func applyStyle(to button: UIButton, action: KeyAction, active: Bool) {
        if action.isTmux {
            button.backgroundColor = active ? accentColor.withAlphaComponent(0.18) : tmuxKeyBg
            button.setTitleColor(accentColor, for: .normal)
            button.tintColor = accentColor
            button.layer.borderColor = tmuxBorder.cgColor
        } else if action.isSpecial {
            button.backgroundColor = active ? keyActiveBg : keySpecialBg
            button.setTitleColor(active ? accentColor : textDim, for: .normal)
            button.tintColor = active ? accentColor : textDim
            button.layer.borderColor = (active ? tmuxBorder : keyBorder).cgColor
        } else {
            button.backgroundColor = active ? keyActiveBg : keyBg
            button.setTitleColor(textColor, for: .normal)
            button.tintColor = textColor
            button.layer.borderColor = (active ? tmuxBorder : keyBorder).cgColor
        }
    }

    private static var actionKey: UInt8 = 0

    private func action(for button: UIButton) -> KeyAction? {
        objc_getAssociatedObject(button, &KeyBarView.actionKey) as? KeyAction
    }

    private func makeBackButton() -> UIButton {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        button.setImage(UIImage(systemName: "chevron.backward", withConfiguration: config), for: .normal)
        button.tintColor = textDim
        button.backgroundColor = keySpecialBg
        button.layer.cornerRadius = 7
        button.layer.borderWidth = 1
        button.layer.borderColor = keyBorder.cgColor
        button.clipsToBounds = true
        button.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 30),
            button.widthAnchor.constraint(equalToConstant: 30),
        ])
        return button
    }

    @objc private func backTapped() {
        UIDevice.current.playInputClick()
        dismissKeyboardForDeferredUITransition()
        DispatchQueue.main.async { [weak self] in
            self?.onBackTapped?()
        }
    }

    private func makeTmuxMenuButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(String(localized: "tmux"), for: .normal)
        button.titleLabel?.font = .monospacedSystemFont(ofSize: 10, weight: .bold)
        button.setTitleColor(accentColor, for: .normal)
        button.backgroundColor = tmuxKeyBg
        button.layer.cornerRadius = 7
        button.layer.borderWidth = 1
        button.layer.borderColor = tmuxBorder.cgColor
        button.clipsToBounds = true
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 9, bottom: 0, right: 9)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 30),
        ])
        button.addTarget(self, action: #selector(tmuxMenuTapped), for: .touchUpInside)
        return button
    }

    @objc private func tmuxMenuTapped() {
        UIDevice.current.playInputClick()
        dismissKeyboardForDeferredUITransition()
        DispatchQueue.main.async { [weak self] in
            self?.onTmuxMenuTapped?()
        }
    }

    private func makeKeyboardDismissButton() -> UIButton {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        button.setImage(UIImage(systemName: "keyboard.chevron.compact.down", withConfiguration: config), for: .normal)
        button.tintColor = textDim
        button.backgroundColor = keySpecialBg
        button.layer.cornerRadius = 7
        button.layer.borderWidth = 1
        button.layer.borderColor = keyBorder.cgColor
        button.clipsToBounds = true
        button.addTarget(self, action: #selector(keyboardDismissTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 30),
            button.widthAnchor.constraint(equalToConstant: 34),
        ])
        return button
    }

    @objc private func keyboardDismissTapped() {
        UIDevice.current.playInputClick()
        terminalView?.resignFirstResponder()
    }

    private func makeGearButton() -> UIButton {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        button.setImage(UIImage(systemName: "slider.horizontal.3", withConfiguration: config), for: .normal)
        button.tintColor = textDim
        button.backgroundColor = keySpecialBg
        button.layer.cornerRadius = 7
        button.layer.borderWidth = 1
        button.layer.borderColor = keyBorder.cgColor
        button.clipsToBounds = true
        button.addTarget(self, action: #selector(gearTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 30),
            button.widthAnchor.constraint(equalToConstant: 30),
        ])
        return button
    }

    @objc private func gearTapped() {
        dismissKeyboardForDeferredUITransition()
        DispatchQueue.main.async { [weak self] in
            self?.onCustomizeTapped?()
        }
    }

    private func dismissKeyboardForDeferredUITransition() {
        _ = terminalView?.resignFirstResponder()
    }

    @objc private func keyDown(_ sender: UIButton) {
        guard let action = action(for: sender) else { return }
        UIDevice.current.playInputClick()

        applyStyle(to: sender, action: action, active: true)

        if action.supportsAutoRepeat {
            startAutoRepeat(action)
        } else {
            executeAction(action, button: sender)
        }
    }

    @objc private func keyUp(_ sender: UIButton) {
        if let action = action(for: sender), (!action.isToggle || !ctrlActive) {
            applyStyle(to: sender, action: action, active: false)
        }
        cancelAutoRepeat()
    }

    private func executeAction(_ action: KeyAction, button: UIButton? = nil) {
        guard let terminalView else { return }
        let handled = action.execute(on: terminalView)
        if !handled && action == .ctrl {
            ctrlActive = terminalView.controlModifier
            updateCtrlButton()
        }
    }

    private func updateCtrlButton() {
        for view in stackView.arrangedSubviews {
            guard let button = view as? UIButton,
                  let action = action(for: button),
                  action == .ctrl else { continue }
            applyStyle(to: button, action: action, active: ctrlActive)
        }
    }

    private func startAutoRepeat(_ action: KeyAction) {
        cancelAutoRepeat()
        repeatAction = action
        executeAction(action)

        repeatTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.075, repeats: true) { [weak self] _ in
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

extension KeyBarView: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateFadeVisibility()
    }
}
#endif
