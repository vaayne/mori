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
    let path: String

    var id: String { "\(sessionName):\(index)" }

    var shortPath: String {
        guard !path.isEmpty else { return "" }
        let display = path.contains("/Users/") || path.contains("/home/")
            ? "~" + path.split(separator: "/").dropFirst(2).map { "/" + $0 }.joined()
            : path
        let parts = display.split(separator: "/")
        if parts.count <= 2 { return display }
        return "…/" + parts.suffix(2).joined(separator: "/")
    }

    init(index: Int, name: String, isActive: Bool, sessionName: String = "", path: String = "") {
        self.index = index
        self.name = name
        self.isActive = isActive
        self.sessionName = sessionName
        self.path = path
    }
}

@MainActor
protocol TmuxBarDelegate: AnyObject {
    func tmuxBarDidTap()
}

/// Compact status pill showing the active tmux session and window.
@MainActor
final class TmuxBarView: UIView {

    weak var delegate: TmuxBarDelegate?

    private let pillButton = UIButton(type: .system)
    private(set) var currentSession: TmuxSession?
    private(set) var windows: [TmuxWindow] = []

    private let accentColor = UIColor.tintColor
    private let pillBg = UIColor.tintColor.withAlphaComponent(0.12)
    private let borderColor = UIColor.tintColor.withAlphaComponent(0.28)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        pillButton.backgroundColor = pillBg
        pillButton.layer.cornerRadius = 7
        pillButton.layer.borderWidth = 1
        pillButton.layer.borderColor = borderColor.cgColor
        pillButton.clipsToBounds = true
        pillButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 9, bottom: 4, right: 9)
        pillButton.addTarget(self, action: #selector(pillTapped), for: .touchUpInside)
        pillButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pillButton)

        NSLayoutConstraint.activate([
            pillButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            pillButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            pillButton.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

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

        text.append(NSAttributedString(
            string: "⬡ ",
            attributes: [
                .font: UIFont.systemFont(ofSize: 9, weight: .bold),
                .foregroundColor: accentColor,
            ]
        ))

        text.append(NSAttributedString(
            string: session.name,
            attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: accentColor,
            ]
        ))

        if let window = activeWindow {
            text.append(NSAttributedString(
                string: "  ›  ",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
                    .foregroundColor: accentColor.withAlphaComponent(0.5),
                ]
            ))
            text.append(NSAttributedString(
                string: window.name,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 10, weight: .medium),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.92),
                ]
            ))
        }

        pillButton.setAttributedTitle(text, for: .normal)
    }

    @objc private func pillTapped() {
        delegate?.tmuxBarDidTap()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 34)
    }
}
#endif
