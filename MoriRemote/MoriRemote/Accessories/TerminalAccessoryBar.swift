#if os(iOS)
import SwiftTerm
import UIKit

/// Single-row input accessory view for the terminal keyboard.
/// Contains the compact Mori-style quick key bar.
@MainActor
final class TerminalAccessoryBar: UIInputView, UIInputViewAudioFeedback {

    let keyBar = KeyBarView()

    weak var terminalView: SwiftTerm.TerminalView? {
        didSet { keyBar.terminalView = terminalView }
    }

    /// Callback for tmux commands from the key bar.
    var onTmuxCommand: ((TmuxCommand) -> Void)?

    /// Called when the user taps the tmux menu button.
    var onTmuxMenuTapped: (() -> Void)?

    /// Called when the user taps the gear button to customize the key bar.
    var onCustomizeTapped: (() -> Void)?

    var enableInputClicksWhenVisible: Bool { true }

    private let barBg = UIColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1)
    private let topBorder = UIView()

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 45), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        backgroundColor = barBg
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        topBorder.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        topBorder.translatesAutoresizingMaskIntoConstraints = false

        keyBar.translatesAutoresizingMaskIntoConstraints = false

        addSubview(topBorder)
        addSubview(keyBar)

        keyBar.onCustomizeTapped = { [weak self] in
            self?.onCustomizeTapped?()
        }
        keyBar.onTmuxMenuTapped = { [weak self] in
            self?.onTmuxMenuTapped?()
        }
        keyBar.onTmuxAction = { [weak self] cmd in
            self?.onTmuxCommand?(cmd)
        }

        NSLayoutConstraint.activate([
            topBorder.topAnchor.constraint(equalTo: topAnchor),
            topBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBorder.heightAnchor.constraint(equalToConstant: 1),

            keyBar.topAnchor.constraint(equalTo: topBorder.bottomAnchor),
            keyBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            keyBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            keyBar.heightAnchor.constraint(equalToConstant: 44),
            keyBar.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func updateTmux(session: TmuxSession?, windows: [TmuxWindow]) {
        // Kept for ShellCoordinator compatibility.
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 45)
    }
}

// MARK: - Tmux Command

enum TmuxCommand: Sendable {
    case selectWindow(Int)
    case newWindow
    case nextWindow
    case prevWindow
    case splitRight
    case splitDown
    case nextPane
    case prevPane
    case toggleZoom
    case closePane
    case showSessionPicker
    case switchSession(String)
    case detach

    func shellCommand(session: String? = nil) -> String {
        switch self {
        case .selectWindow(let idx): return "tmux select-window -t :\(idx)"
        case .newWindow:             return "tmux new-window"
        case .nextWindow:            return "tmux next-window"
        case .prevWindow:            return "tmux previous-window"
        case .splitRight:            return "tmux split-window -h"
        case .splitDown:             return "tmux split-window -v"
        case .nextPane:              return "tmux select-pane -t :.+"
        case .prevPane:              return "tmux select-pane -t :.-"
        case .toggleZoom:            return "tmux resize-pane -Z"
        case .closePane:             return "tmux kill-pane"
        case .showSessionPicker:     return "tmux switch-client -n"
        case .switchSession(let n):  return "tmux switch-client -t '\(n)'"
        case .detach:                return "tmux detach-client"
        }
    }
}
#endif
