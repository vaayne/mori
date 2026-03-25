import UIKit
import GhosttyKit

/// Input accessory view providing terminal-specific keys (Ctrl, Esc, Tab, arrows, etc.)
/// that are not available on the standard iOS keyboard.
@MainActor
final class TerminalInputAccessoryView: UIView {

    /// Callback invoked when a special key is tapped. Sends raw bytes to the pipe bridge.
    var onKeyPress: ((Data) -> Void)?

    private var isCtrlActive = false
    private var ctrlButton: UIButton?

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: frame.width, height: 44))
        autoresizingMask = .flexibleWidth
        setupBar()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupBar() {
        backgroundColor = UIColor.systemBackground.withAlphaComponent(0.95)

        let blurEffect = UIBlurEffect(style: .systemMaterial)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)
        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Top separator
        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
        ])

        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])

        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 6
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        // Key definitions: (label, bytes when pressed)
        let keys: [(String, KeyAction)] = [
            ("Esc", .bytes(Data([0x1B]))),
            ("Ctrl", .toggle),
            ("Tab", .bytes(Data([0x09]))),
            ("|", .bytes(Data([0x7C]))),
            ("~", .bytes(Data([0x7E]))),
            ("-", .bytes(Data([0x2D]))),
            ("/", .bytes(Data([0x2F]))),
            ("\u{2190}", .bytes(Data([0x1B, 0x5B, 0x44]))),  // Left arrow: ESC [ D
            ("\u{2191}", .bytes(Data([0x1B, 0x5B, 0x41]))),  // Up arrow: ESC [ A
            ("\u{2193}", .bytes(Data([0x1B, 0x5B, 0x42]))),  // Down arrow: ESC [ B
            ("\u{2192}", .bytes(Data([0x1B, 0x5B, 0x43]))),  // Right arrow: ESC [ C
        ]

        for (index, (label, action)) in keys.enumerated() {
            let button = makeKeyButton(label: label, tag: index)

            switch action {
            case .bytes:
                button.addAction(UIAction { [weak self] _ in
                    self?.handleKeyPress(action: action)
                }, for: .touchUpInside)
            case .toggle:
                button.addAction(UIAction { [weak self] _ in
                    self?.toggleCtrl(button)
                }, for: .touchUpInside)
                self.ctrlButton = button
            }

            stackView.addArrangedSubview(button)
        }
    }

    // MARK: - Key Handling

    private enum KeyAction {
        case bytes(Data)
        case toggle
    }

    private func handleKeyPress(action: KeyAction) {
        switch action {
        case .bytes(let data):
            if isCtrlActive {
                isCtrlActive = false
                updateCtrlAppearance()

                // For single printable ASCII bytes, send the Ctrl-modified character
                if data.count == 1, let byte = data.first {
                    let upper = byte & 0xDF // force uppercase
                    if upper >= 0x40 && upper <= 0x5F {
                        // Ctrl+letter/symbol: e.g. Ctrl+C = 0x03
                        onKeyPress?(Data([upper - 0x40]))
                        return
                    }
                }

                // For escape sequences (arrows) and other multi-byte keys,
                // send the bytes unmodified — Ctrl does not apply.
                onKeyPress?(data)
            } else {
                onKeyPress?(data)
            }
        case .toggle:
            break // handled by toggleCtrl
        }
    }

    private func toggleCtrl(_ button: UIButton) {
        isCtrlActive.toggle()
        updateCtrlAppearance()
    }

    private func updateCtrlAppearance() {
        guard let ctrlButton else { return }
        if isCtrlActive {
            ctrlButton.backgroundColor = .systemBlue
            ctrlButton.setTitleColor(.white, for: .normal)
        } else {
            ctrlButton.backgroundColor = UIColor.secondarySystemBackground
            ctrlButton.setTitleColor(.label, for: .normal)
        }
    }

    /// Send a Ctrl+letter combination. Called when Ctrl is active and a letter key is pressed.
    func sendCtrlKey(letter: Character) {
        guard let ascii = letter.asciiValue else { return }
        // Ctrl+A = 0x01, Ctrl+B = 0x02, ... Ctrl+Z = 0x1A
        let upper = ascii & 0xDF // force uppercase
        if upper >= 0x40 && upper <= 0x5F {
            let ctrlByte = upper - 0x40
            onKeyPress?(Data([ctrlByte]))
        }
        isCtrlActive = false
        updateCtrlAppearance()
    }

    // MARK: - Button Factory

    private func makeKeyButton(label: String, tag: Int) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(label, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        button.setTitleColor(.label, for: .normal)
        button.backgroundColor = UIColor.secondarySystemBackground
        button.layer.cornerRadius = 6
        button.layer.masksToBounds = true
        button.tag = tag
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
            button.heightAnchor.constraint(equalToConstant: 32),
        ])
        button.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        return button
    }
}
