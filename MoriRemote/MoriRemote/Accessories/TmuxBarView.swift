#if os(iOS)
import UIKit

// MARK: - Tmux Data Types

struct TmuxSession: Equatable, Sendable, Identifiable {
    let name: String
    let windowCount: Int
    let isAttached: Bool
    var windows: [TmuxWindow] = []

    var id: String { name }
}

struct TmuxWindow: Equatable, Sendable, Identifiable {
    let index: Int
    let name: String
    let isActive: Bool
    let sessionName: String

    var id: String { "\(sessionName):\(index)" }

    init(index: Int, name: String, isActive: Bool, sessionName: String = "") {
        self.index = index
        self.name = name
        self.isActive = isActive
        self.sessionName = sessionName
    }
}

// MARK: - Delegate

@MainActor
protocol TmuxBarDelegate: AnyObject {
    func tmuxBarDidTap()
}

// MARK: - TmuxBarView

/// Compact status pill showing the active tmux session and window.
///
/// Displays as a single tappable pill: "⬡ session › window_name".
/// Hidden when no tmux session is detected.
@MainActor
final class TmuxBarView: UIView {

    weak var delegate: TmuxBarDelegate?

    private let pillButton = UIButton(type: .system)

    // State
    private(set) var currentSession: TmuxSession?
    private(set) var windows: [TmuxWindow] = []

    // Colors
    private let accentColor = UIColor(red: 0.30, green: 0.85, blue: 0.75, alpha: 1)
    private let pillBg = UIColor(red: 0.118, green: 0.118, blue: 0.149, alpha: 1)
    private let borderColor = UIColor.white.withAlphaComponent(0.06)

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        // Bottom border
        let border = UIView()
        border.backgroundColor = borderColor
        border.translatesAutoresizingMaskIntoConstraints = false
        addSubview(border)

        pillButton.backgroundColor = pillBg
        pillButton.layer.cornerRadius = 6
        pillButton.layer.borderWidth = 1
        pillButton.layer.borderColor = accentColor.withAlphaComponent(0.2).cgColor
        pillButton.clipsToBounds = true
        pillButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        pillButton.addTarget(self, action: #selector(pillTapped), for: .touchUpInside)
        pillButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pillButton)

        NSLayoutConstraint.activate([
            pillButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            pillButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            pillButton.heightAnchor.constraint(equalToConstant: 26),

            border.leadingAnchor.constraint(equalTo: leadingAnchor),
            border.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.bottomAnchor.constraint(equalTo: bottomAnchor),
            border.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    // MARK: - Update

    func update(session: TmuxSession?, windows: [TmuxWindow]) {
        self.currentSession = session
        self.windows = windows
        rebuild()
    }

    private func rebuild() {
        guard let session = currentSession else {
            isHidden = true
            return
        }
        isHidden = false

        let activeWindow = windows.first(where: { $0.isActive })
        let text = NSMutableAttributedString()

        // Session icon
        text.append(NSAttributedString(
            string: "⬡ ",
            attributes: [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: accentColor,
            ]
        ))

        // Session name
        text.append(NSAttributedString(
            string: session.name,
            attributes: [
                .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: accentColor,
            ]
        ))

        // Separator + active window name
        if let win = activeWindow {
            text.append(NSAttributedString(
                string: " › ",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 10),
                    .foregroundColor: accentColor.withAlphaComponent(0.4),
                ]
            ))
            text.append(NSAttributedString(
                string: win.name,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: accentColor.withAlphaComponent(0.7),
                ]
            ))
        }

        pillButton.setAttributedTitle(text, for: .normal)
    }

    // MARK: - Actions

    @objc private func pillTapped() {
        delegate?.tmuxBarDidTap()
    }

    // MARK: - Layout

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 34)
    }
}
#endif
