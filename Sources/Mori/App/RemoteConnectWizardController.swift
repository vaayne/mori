import AppKit
import MoriCore

@MainActor
struct RemoteConnectInput: Sendable {
    var host: String
    var user: String?
    var port: Int?
    var path: String
    var authMethod: SSHAuthMethod
    var password: String?
}

@MainActor
final class RemoteConnectWizardController: NSWindowController {

    typealias SubmitHandler = @MainActor (RemoteConnectInput) async -> Result<Void, any Error>

    private enum Step {
        case host
        case auth
        case password
        case path
        case connecting
    }

    var onSubmit: SubmitHandler?

    private weak var presentingWindow: NSWindow?
    private var step: Step = .host

    private var parsedHost: String = ""
    private var parsedUser: String?
    private var parsedPort: Int?
    private var authMethod: SSHAuthMethod = .publicKey
    private var remotePath: String = ""
    private var password: String?

    /// Set when the user chooses “Use This Mac”; cleared after host step if the host field is edited away.
    private var suggestLocalHomeForPath = false
    private var thisMacFilledHost: String?

    private let titleLabel = NSTextField(labelWithString: "")
    private let stepLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let helperLabel = NSTextField(labelWithString: "")
    private let inputField = NSTextField(string: "")
    private let secureInputField = NSSecureTextField(string: "")
    private let authControl = NSSegmentedControl(labels: ["SSH Key / Agent", "Password"], trackingMode: .selectOne, target: nil, action: nil)
    private let progressIndicator = NSProgressIndicator()
    private let errorLabel = NSTextField(labelWithString: "")

    private let backButton = NSButton(title: "Back", target: nil, action: nil)
    private let continueButton = NSButton(title: "Continue", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let useThisMacButton = NSButton(title: "", target: nil, action: nil)
    private let useThisMacHelpButton = NSButton(title: "", target: nil, action: nil)
    private let useThisMacRow = NSStackView()

    private let stack = NSStackView()

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hasShadow = true

        panel.contentMinSize = NSSize(width: 440, height: 160)

        super.init(window: panel)
        setupUI()
        transition(to: .host)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(over window: NSWindow?) {
        guard let panel = self.window else { return }
        presentingWindow = window
        if let window {
            window.beginSheet(panel)
        } else {
            showWindow(nil)
            panel.center()
        }
        panel.makeKeyAndOrderFront(nil)
    }

    private func dismissWizard() {
        if let panel = self.window, let presentingWindow {
            presentingWindow.endSheet(panel)
        } else {
            self.window?.orderOut(nil)
        }
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        stepLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        stepLabel.textColor = .secondaryLabelColor
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.setContentHuggingPriority(.required, for: .vertical)
        subtitleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        helperLabel.font = .systemFont(ofSize: 11)
        helperLabel.textColor = .tertiaryLabelColor
        helperLabel.lineBreakMode = .byTruncatingTail
        helperLabel.setContentHuggingPriority(.required, for: .vertical)
        helperLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        inputField.placeholderString = ""
        inputField.font = .systemFont(ofSize: 16)
        inputField.bezelStyle = .roundedBezel
        secureInputField.placeholderString = ""
        secureInputField.font = .systemFont(ofSize: 16)
        secureInputField.bezelStyle = .roundedBezel

        authControl.selectedSegment = 0
        authControl.setContentHuggingPriority(.required, for: .vertical)
        authControl.setContentCompressionResistancePriority(.required, for: .vertical)

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .regular
        progressIndicator.isDisplayedWhenStopped = false

        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.textColor = .systemRed
        errorLabel.lineBreakMode = .byTruncatingTail
        errorLabel.isHidden = true

        backButton.target = self
        backButton.action = #selector(backTapped)
        continueButton.target = self
        continueButton.action = #selector(continueTapped)
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)

        useThisMacButton.title = String.localized("Use This Mac")
        useThisMacButton.toolTip = String.localized("Fill your macOS account name and this computer’s LAN IP (for SSH from MoriRemote or another device).")
        useThisMacButton.target = self
        useThisMacButton.action = #selector(useThisMacTapped)
        useThisMacButton.bezelStyle = .rounded
        useThisMacButton.isHidden = true

        if let helpIcon = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: String.localized("SSH tmux check help")) {
            helpIcon.isTemplate = true
            useThisMacHelpButton.image = helpIcon
        }
        useThisMacHelpButton.isBordered = false
        useThisMacHelpButton.toolTip = String.localized("Copy the same ssh + tmux -V probe Mori uses (details in the sheet).")
        useThisMacHelpButton.target = self
        useThisMacHelpButton.action = #selector(useThisMacHelpTapped)
        useThisMacHelpButton.isHidden = true

        useThisMacRow.orientation = .horizontal
        useThisMacRow.alignment = .centerY
        useThisMacRow.spacing = 8
        useThisMacRow.distribution = .fill
        useThisMacRow.addArrangedSubview(useThisMacButton)
        useThisMacRow.addArrangedSubview(useThisMacHelpButton)
        useThisMacButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        useThisMacHelpButton.setContentHuggingPriority(.required, for: .horizontal)
        useThisMacRow.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = NSStackView(views: [cancelButton, NSView(), backButton, continueButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        let headerRow = NSStackView(views: [titleLabel, NSView(), stepLabel])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 8

        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .leading
        stack.setContentHuggingPriority(.defaultHigh, for: .vertical)
        stack.translatesAutoresizingMaskIntoConstraints = false

        [headerRow, subtitleLabel, helperLabel, useThisMacRow, inputField, secureInputField, authControl, progressIndicator, errorLabel, buttonRow].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview($0)
        }

        secureInputField.isHidden = true
        authControl.isHidden = true
        progressIndicator.isHidden = true
        useThisMacRow.isHidden = true

        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -14),
            inputField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            secureInputField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            authControl.widthAnchor.constraint(equalTo: stack.widthAnchor),
            useThisMacRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        inputField.delegate = self
        secureInputField.delegate = self
    }

    private func transition(to next: Step) {
        step = next
        clearError()

        inputField.isHidden = true
        secureInputField.isHidden = true
        authControl.isHidden = true
        useThisMacButton.isHidden = true
        useThisMacHelpButton.isHidden = true
        useThisMacRow.isHidden = true
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true

        switch next {
        case .host:
            titleLabel.stringValue = "Remote: Connect to Host"
            stepLabel.stringValue = "STEP 1"
            subtitleLabel.stringValue = "Enter [user@]host[:port]"
            helperLabel.stringValue = "Examples: dev@server, server:2222, dev@server:2222"
            inputField.placeholderString = "e.g. dev@server or server:2222"
            inputField.stringValue = composeHostFieldValue()
            inputField.isHidden = false
            useThisMacRow.isHidden = false
            useThisMacButton.isHidden = false
            useThisMacHelpButton.isHidden = false
            backButton.isHidden = true
            continueButton.isEnabled = true
            continueButton.title = "Continue"
            inputField.becomeFirstResponder()

        case .auth:
            titleLabel.stringValue = "Authentication"
            stepLabel.stringValue = "STEP 2"
            subtitleLabel.stringValue = "Choose how Mori should authenticate with the remote host"
            helperLabel.stringValue = "SSH key/agent is recommended for reliable background polling."
            authControl.selectedSegment = authMethod == .password ? 1 : 0
            authControl.isHidden = false
            backButton.isHidden = false
            continueButton.isEnabled = true
            continueButton.title = "Continue"

        case .password:
            titleLabel.stringValue = "Password Authentication"
            stepLabel.stringValue = "STEP 3"
            subtitleLabel.stringValue = "Enter the SSH password for this host"
            helperLabel.stringValue = "Password is stored securely in Keychain and reused across restarts."
            secureInputField.placeholderString = "Password"
            secureInputField.stringValue = password ?? ""
            secureInputField.isHidden = false
            backButton.isHidden = false
            continueButton.isEnabled = true
            continueButton.title = "Continue"
            secureInputField.becomeFirstResponder()

        case .path:
            titleLabel.stringValue = "Repository Path"
            stepLabel.stringValue = authMethod == .password ? "STEP 4" : "STEP 3"
            subtitleLabel.stringValue = "Enter absolute repository path on remote host"
            helperLabel.stringValue = "Git repository is optional. Mori can manage plain remote directories too."
            inputField.placeholderString = "/home/dev/project"
            if remotePath.isEmpty, suggestLocalHomeForPath {
                remotePath = NSHomeDirectory()
                suggestLocalHomeForPath = false
            }
            inputField.stringValue = remotePath
            inputField.isHidden = false
            backButton.isHidden = false
            continueButton.isEnabled = true
            continueButton.title = "Connect"
            inputField.becomeFirstResponder()

        case .connecting:
            titleLabel.stringValue = "Connecting"
            stepLabel.stringValue = "FINALIZING"
            subtitleLabel.stringValue = "Validating SSH, tmux, and git repository..."
            helperLabel.stringValue = "This usually takes a few seconds."
            progressIndicator.isHidden = false
            progressIndicator.startAnimation(nil)
            backButton.isHidden = true
            continueButton.isEnabled = false
            continueButton.title = "Connecting..."
        }

        adjustPanelHeightToFitStack()
    }

    /// Keeps the sheet compact per step (fixed tall height + fill distribution left a large gap on Authentication).
    private func adjustPanelHeightToFitStack() {
        guard let window = window, let contentView = window.contentView else { return }
        contentView.needsLayout = true
        contentView.layoutSubtreeIfNeeded()
        let verticalMargins: CGFloat = 18 + 14
        let fit = stack.fittingSize
        let contentHeight = ceil(fit.height + verticalMargins)
        let clamped = min(420, max(168, contentHeight))
        var size = window.contentLayoutRect.size
        guard abs(size.height - clamped) > 0.5 else { return }
        size.height = clamped
        window.setContentSize(size)
    }

    private func composeHostFieldValue() -> String {
        var result = ""
        if let parsedUser, !parsedUser.isEmpty {
            result += "\(parsedUser)@"
        }
        result += parsedHost
        if let parsedPort {
            result += ":\(parsedPort)"
        }
        return result
    }

    private func parseHostInput(_ raw: String) throws -> (host: String, user: String?, port: Int?) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw WizardError.hostEmpty
        }

        var user: String?
        var hostAndPort = trimmed

        if let at = trimmed.firstIndex(of: "@") {
            let userPart = String(trimmed[..<at]).trimmingCharacters(in: .whitespaces)
            let remaining = String(trimmed[trimmed.index(after: at)...]).trimmingCharacters(in: .whitespaces)
            guard !userPart.isEmpty else {
                throw WizardError.hostInvalid("Missing username before @")
            }
            guard !remaining.isEmpty else {
                throw WizardError.hostInvalid("Missing host after @")
            }
            user = userPart
            hostAndPort = remaining
        }

        var host = hostAndPort
        var port: Int?

        if let colon = hostAndPort.lastIndex(of: ":") {
            let hostPart = String(hostAndPort[..<colon]).trimmingCharacters(in: .whitespaces)
            let portPart = String(hostAndPort[hostAndPort.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if !hostPart.isEmpty, !portPart.isEmpty, portPart.allSatisfy({ $0.isNumber }) {
                host = hostPart
                port = Int(portPart)
            }
        }

        guard !host.isEmpty else {
            throw WizardError.hostEmpty
        }

        if let port, !(1...65535).contains(port) {
            throw WizardError.hostInvalid("Port must be between 1 and 65535")
        }

        return (host, user, port)
    }

    @objc private func backTapped() {
        switch step {
        case .auth:
            transition(to: .host)
        case .password:
            transition(to: .auth)
        case .path:
            transition(to: authMethod == .password ? .password : .auth)
        default:
            break
        }
    }

    @objc private func cancelTapped() {
        dismissWizard()
    }

    @objc private func useThisMacTapped() {
        guard let ip = LocalNetworkAddress.preferredIPv4() else {
            showError(String.localized("Could not find a local network IP address. Check Wi‑Fi or Ethernet."))
            return
        }
        clearError()
        thisMacFilledHost = ip
        suggestLocalHomeForPath = true
        inputField.stringValue = "\(NSUserName())@\(ip)"
    }

    @objc private func useThisMacHelpTapped() {
        guard let panel = window else { return }
        let alert = NSAlert()
        alert.messageText = String.localized("SSH tmux check")
        alert.informativeText = String.localized(
            "Turn on Remote Login on this Mac first (System Settings → General → Sharing → Remote Login) so MoriRemote or other devices can connect over SSH.\n\nCopies one ssh command (same as Mori) so your login shell runs tmux -V on the host. If the host field is empty, the command uses your macOS account name and this Mac’s detected LAN IPv4. Otherwise it uses what you typed (or click “Use This Mac” to fill user@IP)."
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: String.localized("OK"))
        alert.addButton(withTitle: String.localized("Copy SSH tmux check"))
        alert.beginSheetModal(for: panel) { [weak self] response in
            guard let self, response == NSApplication.ModalResponse.alertSecondButtonReturn else { return }
            guard let command = self.sshTmuxProbeCommandFromHostField() else {
                self.showError(String.localized("Could not find a local network IP address. Check Wi‑Fi or Ethernet."))
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        }
    }

    /// One-line probe matching Mori’s remote login-shell wrapper (`SSHCommandSupport.remoteLoginShellCommand`).
    /// When the host field is empty, requires a detected LAN IPv4 (same as “Use This Mac”).
    private func sshTmuxProbeCommandFromHostField() -> String? {
        let raw = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty {
            guard let ip = LocalNetworkAddress.preferredIPv4() else { return nil }
            let hostPart = "\(NSUserName())@\(ip)"
            return "ssh \(hostPart) 'exec ${SHELL:-/bin/sh} -l -c \"tmux -V\"'"
        }
        if let parsed = try? parseHostInput(raw) {
            var cmd = "ssh "
            if let port = parsed.port {
                cmd += "-p \(port) "
            }
            var target = ""
            if let user = parsed.user, !user.isEmpty {
                target += "\(user)@"
            }
            target += parsed.host
            cmd += "\(target) 'exec ${SHELL:-/bin/sh} -l -c \"tmux -V\"'"
            return cmd
        }
        // Fallback: parse failed, show error instead of interpolating unsanitized input into a shell command
        return nil
    }

    @objc private func continueTapped() {
        switch step {
        case .host:
            do {
                let parsed = try parseHostInput(inputField.stringValue)
                if parsed.host != thisMacFilledHost {
                    suggestLocalHomeForPath = false
                }
                thisMacFilledHost = nil
                parsedHost = parsed.host
                parsedUser = parsed.user
                parsedPort = parsed.port
                transition(to: .auth)
            } catch {
                showError(error.localizedDescription)
            }

        case .auth:
            authMethod = authControl.selectedSegment == 1 ? .password : .publicKey
            if authMethod == .password {
                transition(to: .password)
            } else {
                transition(to: .path)
            }

        case .password:
            let value = secureInputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                showError("Password is required.")
                return
            }
            password = value
            transition(to: .path)

        case .path:
            let value = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                showError("Remote repository path is required.")
                return
            }
            remotePath = value
            submit()

        case .connecting:
            break
        }
    }

    private func submit() {
        guard let onSubmit else { return }
        transition(to: .connecting)

        let payload = RemoteConnectInput(
            host: parsedHost,
            user: parsedUser,
            port: parsedPort,
            path: remotePath,
            authMethod: authMethod,
            password: password
        )

        Task { [weak self] in
            guard let self else { return }
            let result = await onSubmit(payload)
            switch result {
            case .success:
                self.dismissWizard()
            case .failure(let error):
                self.transition(to: .path)
                self.showError(error.localizedDescription)
            }
        }
    }

    private func clearError() {
        errorLabel.stringValue = ""
        errorLabel.isHidden = true
    }

    private func showError(_ message: String) {
        errorLabel.stringValue = message
        errorLabel.isHidden = false
    }
}

extension RemoteConnectWizardController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        clearError()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            continueTapped()
            return true
        }
        if commandSelector == #selector(cancelOperation(_:)) {
            cancelTapped()
            return true
        }
        return false
    }
}

private enum WizardError: LocalizedError {
    case hostEmpty
    case hostInvalid(String)

    var errorDescription: String? {
        switch self {
        case .hostEmpty:
            return "Remote host cannot be empty."
        case .hostInvalid(let message):
            return message
        }
    }
}
