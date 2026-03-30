#if os(iOS)
import SwiftTerm
import UIKit

/// Two-row input accessory view for the terminal keyboard.
///
/// Top row: `TmuxBarView` — tmux session/window switching (hidden when no tmux).
/// Bottom row: `KeyBarView` — customizable quick keys.
@MainActor
final class TerminalAccessoryBar: UIInputView, UIInputViewAudioFeedback {

    let tmuxBar = TmuxBarView()
    let keyBar = KeyBarView()

    weak var terminalView: SwiftTerm.TerminalView? {
        didSet { keyBar.terminalView = terminalView }
    }

    /// Callback for tmux commands (session/window switching, new window).
    /// The bar fires these; the coordinator executes them over SSH.
    var onTmuxCommand: ((TmuxCommand) -> Void)?

    /// Called when the user taps the gear button to customize the key bar.
    var onCustomizeTapped: (() -> Void)?

    // UIInputViewAudioFeedback
    var enableInputClicksWhenVisible: Bool { true }

    private let barBg = UIColor(red: 0.102, green: 0.102, blue: 0.125, alpha: 1) // #1a1a20

    // MARK: - Init

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 78), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        backgroundColor = barBg
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        let topBorder = UIView()
        topBorder.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        topBorder.translatesAutoresizingMaskIntoConstraints = false

        tmuxBar.translatesAutoresizingMaskIntoConstraints = false
        keyBar.translatesAutoresizingMaskIntoConstraints = false

        addSubview(topBorder)
        addSubview(tmuxBar)
        addSubview(keyBar)

        tmuxBar.delegate = self
        keyBar.onCustomizeTapped = { [weak self] in
            self?.onCustomizeTapped?()
        }
        keyBar.onTmuxAction = { [weak self] cmd in
            self?.onTmuxCommand?(cmd)
        }

        // Start with tmux bar hidden
        tmuxBar.isHidden = true

        NSLayoutConstraint.activate([
            topBorder.topAnchor.constraint(equalTo: topAnchor),
            topBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBorder.heightAnchor.constraint(equalToConstant: 1),

            tmuxBar.topAnchor.constraint(equalTo: topBorder.bottomAnchor),
            tmuxBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            tmuxBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            tmuxBar.heightAnchor.constraint(equalToConstant: 34),

            keyBar.topAnchor.constraint(equalTo: tmuxBar.bottomAnchor),
            keyBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            keyBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            keyBar.heightAnchor.constraint(equalToConstant: 44),
            keyBar.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: - Tmux State

    func updateTmux(session: TmuxSession?, windows: [TmuxWindow]) {
        tmuxBar.update(session: session, windows: windows)
        // Recalculate height: tmux bar adds 34pt when visible
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: CGSize {
        let tmuxHeight: CGFloat = tmuxBar.isHidden ? 0 : 34
        return CGSize(width: UIView.noIntrinsicMetric, height: tmuxHeight + 44 + 1)
    }
}

// MARK: - TmuxBarDelegate

extension TerminalAccessoryBar: TmuxBarDelegate {
    func tmuxBarDidSelectWindow(_ window: TmuxWindow) {
        onTmuxCommand?(.selectWindow(window.index))
    }

    func tmuxBarDidRequestNewWindow() {
        onTmuxCommand?(.newWindow)
    }

    func tmuxBarDidTapSession() {
        onTmuxCommand?(.showSessionPicker)
    }
}

// MARK: - Tmux Command

enum TmuxCommand: Sendable {
    // Window/tab management
    case selectWindow(Int)
    case newWindow
    case nextWindow
    case prevWindow

    // Pane management
    case splitRight
    case splitDown
    case nextPane
    case prevPane
    case toggleZoom
    case closePane

    // Session
    case showSessionPicker
    case switchSession(String)
    case detach

    /// The real tmux CLI command to execute via SSH exec channel.
    var shellCommand: String {
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
