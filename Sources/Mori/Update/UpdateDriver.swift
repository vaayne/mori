// MARK: - UpdateDriver
// SPUUserDriver implementation bridging Sparkle callbacks to UpdateState.

import Cocoa
import os
@preconcurrency import Sparkle

/// Returns a closure that forwards to `handler` at most once. Subsequent calls are no-ops.
private func callOnce<T>(_ handler: @escaping @Sendable (T) -> Void) -> @Sendable (T) -> Void {
    let called = OSAllocatedUnfairLock(initialState: false)
    return { value in
        let alreadyCalled = called.withLock { wasCalled in
            let prev = wasCalled
            wasCalled = true
            return prev
        }
        guard !alreadyCalled else { return }
        handler(value)
    }
}

/// Implements SPUUserDriver to translate Sparkle callbacks into UpdateState transitions.
/// Falls back to SPUStandardUserDriver when no visible window is available.
@MainActor
final class UpdateDriver: NSObject, SPUUserDriver {
    let viewModel: UpdateViewModel
    let standard: SPUStandardUserDriver

    /// Called when the user retries after an error. Set by UpdateController.
    var onRetryCheck: (() -> Void)?

    /// Running download byte count — tracked separately to throttle UI updates.
    private var downloadProgress: UInt64 = 0

    /// Cached value of whether a visible MainWindowController exists.
    private var _hasUnobtrusiveTarget = false

    init(viewModel: UpdateViewModel, hostBundle: Bundle) {
        self.viewModel = viewModel
        self.standard = SPUStandardUserDriver(hostBundle: hostBundle, delegate: nil)
        super.init()

        _hasUnobtrusiveTarget = Self.computeHasUnobtrusiveTarget()

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleWindowWillClose),
                       name: NSWindow.willCloseNotification, object: nil)
        nc.addObserver(self, selector: #selector(updateUnobtrusiveTargetCache),
                       name: NSWindow.didBecomeKeyNotification, object: nil)
        nc.addObserver(self, selector: #selector(updateUnobtrusiveTargetCache),
                       name: NSWindow.didResignKeyNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func updateUnobtrusiveTargetCache(_ notification: Notification? = nil) {
        _hasUnobtrusiveTarget = Self.computeHasUnobtrusiveTarget()
    }

    @objc private func handleWindowWillClose(_ notification: Notification) {
        // Only react when the closing window is Mori's main window.
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow.windowController is MainWindowController else { return }

        // If we lost the ability to show unobtrusive states, cancel whatever
        // update state we're in. This allows the manual "check for updates"
        // call to initialize the standard driver.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            self?.updateUnobtrusiveTargetCache()
            guard let self, !hasUnobtrusiveTarget else { return }
            viewModel.state.cancel()
            viewModel.state = .idle
        }
    }

    // MARK: - SPUUserDriver

    func show(_ request: SPUUpdatePermissionRequest,
              reply: @escaping @Sendable (SUUpdatePermissionResponse) -> Void) {
        let safeReply = callOnce(reply)
        viewModel.state = .permissionRequest(.init(request: request, reply: { [weak viewModel] response in
            viewModel?.state = .idle
            safeReply(response)
        }))
        if !hasUnobtrusiveTarget {
            standard.show(request, reply: safeReply)
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
        let safeReply = callOnce(reply)
        viewModel.state = .updateAvailable(.init(appcastItem: appcastItem, reply: safeReply))
        if !hasUnobtrusiveTarget {
            standard.showUpdateFound(with: appcastItem, state: state, reply: safeReply)
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
                Task { @MainActor [weak self] in
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
        downloadProgress = 0
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
            progress: downloadProgress))

        if !hasUnobtrusiveTarget {
            standard.showDownloadDidReceiveExpectedContentLength(expectedContentLength)
        }
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        guard case let .downloading(downloading) = viewModel.state else {
            return
        }

        let oldTotal = downloadProgress
        downloadProgress += length

        // Throttle UI updates: only push state when the integer percentage changes.
        if let expected = downloading.expectedLength, expected > 0 {
            let oldPct = Int(Double(oldTotal) / Double(expected) * 100)
            let newPct = Int(Double(downloadProgress) / Double(expected) * 100)
            if oldPct == newPct {
                if !hasUnobtrusiveTarget {
                    standard.showDownloadDidReceiveData(ofLength: length)
                }
                return
            }
        }

        viewModel.state = .downloading(.init(
            cancel: downloading.cancel,
            expectedLength: downloading.expectedLength,
            progress: downloadProgress))

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

    /// True if there is a visible main window that can render the unobtrusive update badge.
    var hasUnobtrusiveTarget: Bool { _hasUnobtrusiveTarget }

    private static func computeHasUnobtrusiveTarget() -> Bool {
        NSApp.windows.contains { window in
            window.isVisible && window.windowController is MainWindowController
        }
    }
}
