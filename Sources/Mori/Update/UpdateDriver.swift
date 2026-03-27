// MARK: - UpdateDriver
// SPUUserDriver implementation bridging Sparkle callbacks to UpdateState.

import Cocoa
@preconcurrency import Sparkle

/// Implements SPUUserDriver to translate Sparkle callbacks into UpdateState transitions.
/// Falls back to SPUStandardUserDriver when no visible window is available.
class UpdateDriver: NSObject, SPUUserDriver {
    let viewModel: UpdateViewModel
    let standard: SPUStandardUserDriver

    /// Called when the user retries after an error. Set by UpdateController.
    var onRetryCheck: (() -> Void)?

    init(viewModel: UpdateViewModel, hostBundle: Bundle) {
        self.viewModel = viewModel
        self.standard = SPUStandardUserDriver(hostBundle: hostBundle, delegate: nil)
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowWillClose),
            name: NSWindow.willCloseNotification,
            object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleWindowWillClose(_ notification: Notification) {
        // If we lost the ability to show unobtrusive states, cancel whatever
        // update state we're in. This allows the manual "check for updates"
        // call to initialize the standard driver.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) { [weak self] in
            guard let self else { return }
            guard !hasUnobtrusiveTarget else { return }
            viewModel.state.cancel()
            viewModel.state = .idle
        }
    }

    // MARK: - SPUUserDriver

    func show(_ request: SPUUpdatePermissionRequest,
              reply: @escaping @Sendable (SUUpdatePermissionResponse) -> Void) {
        viewModel.state = .permissionRequest(.init(request: request, reply: { [weak viewModel] response in
            viewModel?.state = .idle
            reply(response)
        }))
        if !hasUnobtrusiveTarget {
            standard.show(request, reply: reply)
        }
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        viewModel.state = .checking(.init(cancel: cancellation))

        if !hasUnobtrusiveTarget {
            standard.showUserInitiatedUpdateCheck(cancellation: cancellation)
        }
    }

    func showUpdateFound(with appcastItem: SUAppcastItem,
                         state: SPUUserUpdateState,
                         reply: @escaping @Sendable (SPUUserUpdateChoice) -> Void) {
        viewModel.state = .updateAvailable(.init(appcastItem: appcastItem, reply: reply))
        if !hasUnobtrusiveTarget {
            standard.showUpdateFound(with: appcastItem, state: state, reply: reply)
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        // Mori links to GitHub releases instead of rendering inline release notes.
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {
        // No-op: see showUpdateReleaseNotes.
    }

    func showUpdateNotFoundWithError(_ error: any Error,
                                     acknowledgement: @escaping () -> Void) {
        viewModel.state = .notFound(.init(acknowledgement: acknowledgement))

        if !hasUnobtrusiveTarget {
            standard.showUpdateNotFoundWithError(error, acknowledgement: acknowledgement)
        }
    }

    func showUpdaterError(_ error: any Error,
                          acknowledgement: @escaping () -> Void) {
        viewModel.state = .error(.init(
            error: error,
            retry: { [weak self, weak viewModel] in
                viewModel?.state = .idle
                DispatchQueue.main.async { [weak self] in
                    self?.onRetryCheck?()
                }
            },
            dismiss: { [weak viewModel] in
                viewModel?.state = .idle
            }))

        if !hasUnobtrusiveTarget {
            standard.showUpdaterError(error, acknowledgement: acknowledgement)
        } else {
            acknowledgement()
        }
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        viewModel.state = .downloading(.init(
            cancel: cancellation,
            expectedLength: nil,
            progress: 0))

        if !hasUnobtrusiveTarget {
            standard.showDownloadInitiated(cancellation: cancellation)
        }
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        guard case let .downloading(downloading) = viewModel.state else {
            return
        }

        viewModel.state = .downloading(.init(
            cancel: downloading.cancel,
            expectedLength: expectedContentLength,
            progress: 0))

        if !hasUnobtrusiveTarget {
            standard.showDownloadDidReceiveExpectedContentLength(expectedContentLength)
        }
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        guard case let .downloading(downloading) = viewModel.state else {
            return
        }

        viewModel.state = .downloading(.init(
            cancel: downloading.cancel,
            expectedLength: downloading.expectedLength,
            progress: downloading.progress + length))

        if !hasUnobtrusiveTarget {
            standard.showDownloadDidReceiveData(ofLength: length)
        }
    }

    func showDownloadDidStartExtractingUpdate() {
        viewModel.state = .extracting(.init(progress: 0))

        if !hasUnobtrusiveTarget {
            standard.showDownloadDidStartExtractingUpdate()
        }
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        viewModel.state = .extracting(.init(progress: progress))

        if !hasUnobtrusiveTarget {
            standard.showExtractionReceivedProgress(progress)
        }
    }

    func showReady(toInstallAndRelaunch reply: @escaping @Sendable (SPUUserUpdateChoice) -> Void) {
        if !hasUnobtrusiveTarget {
            standard.showReady(toInstallAndRelaunch: reply)
        } else {
            reply(.install)
        }
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        viewModel.state = .installing(.init(
            retryTerminatingApplication: retryTerminatingApplication,
            dismiss: { [weak viewModel] in
                viewModel?.state = .idle
            }
        ))

        if !hasUnobtrusiveTarget {
            standard.showInstallingUpdate(withApplicationTerminated: applicationTerminated, retryTerminatingApplication: retryTerminatingApplication)
        }
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        standard.showUpdateInstalledAndRelaunched(relaunched, acknowledgement: acknowledgement)
        viewModel.state = .idle
    }

    func showUpdateInFocus() {
        if !hasUnobtrusiveTarget {
            standard.showUpdateInFocus()
        }
    }

    func dismissUpdateInstallation() {
        viewModel.state = .idle
        standard.dismissUpdateInstallation()
    }

    // MARK: - No-Window Fallback

    /// True if there is a visible window that can render the unobtrusive update badge.
    var hasUnobtrusiveTarget: Bool {
        NSApp.windows.contains { window in
            window.isVisible && window.contentViewController != nil
        }
    }
}
