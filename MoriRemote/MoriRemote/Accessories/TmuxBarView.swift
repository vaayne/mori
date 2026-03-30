#if os(iOS)
import UIKit

// MARK: - Tmux Data Types

struct TmuxSession: Equatable, Sendable {
    let name: String
    let windowCount: Int
    let isAttached: Bool
}

struct TmuxWindow: Equatable, Sendable {
    let index: Int
    let name: String
    let isActive: Bool
}

// MARK: - Delegate

@MainActor
protocol TmuxBarDelegate: AnyObject {
    func tmuxBarDidSelectWindow(_ window: TmuxWindow)
    func tmuxBarDidRequestNewWindow()
    func tmuxBarDidTapSession()
}

// MARK: - TmuxBarView

/// Top row of the terminal accessory — shows tmux session and windows.
///
/// Hidden when no tmux session is detected. Scrollable horizontally.
@MainActor
final class TmuxBarView: UIView {

    weak var delegate: TmuxBarDelegate?

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    // State
    private(set) var currentSession: TmuxSession?
    private(set) var windows: [TmuxWindow] = []

    // Colors
    private let accentColor = UIColor(red: 0.30, green: 0.85, blue: 0.75, alpha: 1)
    private let pillBg = UIColor(red: 0.137, green: 0.137, blue: 0.188, alpha: 1)       // #232330
    private let pillActiveBg = UIColor(red: 0.30, green: 0.85, blue: 0.75, alpha: 0.15)
    private let sessionBg = UIColor(red: 0.118, green: 0.118, blue: 0.149, alpha: 1)
    private let textDim = UIColor.white.withAlphaComponent(0.55)
    private let textFaint = UIColor.white.withAlphaComponent(0.35)
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

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        stackView.axis = .horizontal
        stackView.spacing = 6
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -8),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),

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
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        guard let session = currentSession else {
            isHidden = true
            return
        }
        isHidden = false

        // Session pill
        stackView.addArrangedSubview(makeSessionPill(session))

        // Window pills
        for window in windows {
            stackView.addArrangedSubview(makeWindowPill(window))
        }

        // Add button
        stackView.addArrangedSubview(makeAddButton())
    }

    // MARK: - Pill Builders

    private func makeSessionPill(_ session: TmuxSession) -> UIButton {
        let btn = UIButton(type: .system)
        btn.backgroundColor = sessionBg
        btn.layer.cornerRadius = 6
        btn.layer.borderWidth = 1
        btn.layer.borderColor = accentColor.withAlphaComponent(0.2).cgColor
        btn.clipsToBounds = true

        let icon = NSAttributedString(
            string: "⬡ ",
            attributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: accentColor]
        )
        let name = NSAttributedString(
            string: session.name,
            attributes: [.font: UIFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: accentColor]
        )
        let full = NSMutableAttributedString()
        full.append(icon)
        full.append(name)
        btn.setAttributedTitle(full, for: .normal)
        btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)

        btn.addTarget(self, action: #selector(sessionTapped), for: .touchUpInside)

        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return btn
    }

    private func makeWindowPill(_ window: TmuxWindow) -> UIButton {
        let btn = UIButton(type: .system)
        btn.layer.cornerRadius = 6
        btn.clipsToBounds = true
        btn.tag = window.index

        if window.isActive {
            btn.backgroundColor = pillActiveBg
            btn.layer.borderWidth = 1
            btn.layer.borderColor = accentColor.cgColor
        } else {
            btn.backgroundColor = pillBg
            btn.layer.borderWidth = 1
            btn.layer.borderColor = UIColor.clear.cgColor
        }

        let idx = NSAttributedString(
            string: "\(window.index) ",
            attributes: [
                .font: UIFont.systemFont(ofSize: 9),
                .foregroundColor: window.isActive ? accentColor.withAlphaComponent(0.6) : textFaint,
            ]
        )
        let name = NSAttributedString(
            string: window.name,
            attributes: [
                .font: UIFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: window.isActive ? accentColor : textDim,
            ]
        )
        let full = NSMutableAttributedString()
        full.append(idx)
        full.append(name)
        btn.setAttributedTitle(full, for: .normal)
        btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)

        btn.addTarget(self, action: #selector(windowTapped(_:)), for: .touchUpInside)

        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return btn
    }

    private func makeAddButton() -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle("+", for: .normal)
        btn.setTitleColor(textFaint, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 13)
        btn.layer.cornerRadius = 6
        btn.layer.borderWidth = 1
        btn.layer.borderColor = textFaint.cgColor
        btn.clipsToBounds = true
        btn.addTarget(self, action: #selector(addTapped), for: .touchUpInside)

        btn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: 26),
            btn.heightAnchor.constraint(equalToConstant: 26),
        ])
        return btn
    }

    // MARK: - Actions

    @objc private func sessionTapped() {
        delegate?.tmuxBarDidTapSession()
    }

    @objc private func windowTapped(_ sender: UIButton) {
        guard let window = windows.first(where: { $0.index == sender.tag }) else { return }
        delegate?.tmuxBarDidSelectWindow(window)
    }

    @objc private func addTapped() {
        delegate?.tmuxBarDidRequestNewWindow()
    }

    // MARK: - Layout

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 34)
    }
}
#endif
