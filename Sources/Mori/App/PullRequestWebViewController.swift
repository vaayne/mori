import AppKit
import WebKit
import MoriTerminal

@MainActor
final class PullRequestWebViewController: NSViewController {
    private var webView: WKWebView!
    private let headerView = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let dividerView = NSView()

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.translatesAutoresizingMaskIntoConstraints = false

        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.wantsLayer = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = .localized("Pull Request")
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail

        dividerView.translatesAutoresizingMaskIntoConstraints = false
        dividerView.wantsLayer = true

        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.translatesAutoresizingMaskIntoConstraints = false
        wv.underPageBackgroundColor = .clear
        self.webView = wv

        root.addSubview(headerView)
        root.addSubview(dividerView)
        root.addSubview(wv)
        headerView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: root.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -10),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            dividerView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            dividerView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            dividerView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            dividerView.heightAnchor.constraint(equalToConstant: 1),

            wv.topAnchor.constraint(equalTo: dividerView.bottomAnchor),
            wv.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            wv.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        self.view = root
    }

    func loadPullRequest(_ url: URL) {
        titleLabel.stringValue = url.absoluteString
        webView.load(URLRequest(url: url))
    }

    func updateAppearance(themeInfo: GhosttyThemeInfo) {
        view.appearance = NSAppearance(named: themeInfo.isDark ? .darkAqua : .aqua)
        view.layer?.backgroundColor = themeInfo.effectiveBackground.cgColor
        let blend: CGFloat = themeInfo.isDark ? 0.12 : 0.06
        let tint = themeInfo.isDark ? NSColor.white : NSColor.black
        let headerBg = (themeInfo.effectiveBackground.usingColorSpace(.deviceRGB) ?? themeInfo.effectiveBackground)
            .blended(withFraction: blend, of: tint) ?? themeInfo.effectiveBackground
        headerView.layer?.backgroundColor = headerBg.cgColor
        dividerView.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        titleLabel.textColor = .secondaryLabelColor
    }
}
