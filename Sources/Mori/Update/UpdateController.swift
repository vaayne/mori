// MARK: - UpdateController
// Wraps SPUUpdater, manages update lifecycle.

import Cocoa
@preconcurrency import Combine
@preconcurrency import Sparkle

/// Manages the Sparkle updater lifecycle.
@MainActor
final class UpdateController {
    private(set) var updater: SPUUpdater
    private let userDriver: UpdateDriver
    private var installCancellable: AnyCancellable?

    var viewModel: UpdateViewModel {
        userDriver.viewModel
    }

    /// True if we're in a force-install chain.
    var isInstalling: Bool {
        installCancellable != nil
    }

    init() {
        let hostBundle = Bundle.main
        self.userDriver = UpdateDriver(
            viewModel: .init(),
            hostBundle: hostBundle)
        self.updater = SPUUpdater(
            hostBundle: hostBundle,
            applicationBundle: hostBundle,
            userDriver: userDriver,
            delegate: userDriver
        )

        // Wire the retry callback so the driver can trigger a new check.
        userDriver.onRetryCheck = { [weak self] in
            self?.checkForUpdates()
        }
    }

    deinit {
        installCancellable?.cancel()
    }

    /// Start the updater. Must be called before checking for updates.
    func startUpdater() {
        do {
            try updater.start()
        } catch {
            userDriver.viewModel.state = .error(.init(
                error: error,
                retry: { [weak self] in
                    self?.userDriver.viewModel.state = .idle
                    self?.startUpdater()
                },
                dismiss: { [weak self] in
                    self?.userDriver.viewModel.state = .idle
                }
            ))
        }
    }

    /// Force install the current update by auto-confirming each step.
    /// Uses Combine `$state.sink` to create a yes-chain through all states.
    func installUpdate() {
        guard viewModel.state.isInstallable else { return }
        guard installCancellable == nil else { return }

        installCancellable = viewModel.$state.sink { [weak self] state in
            // If we move to a non-installable state, stop force installing.
            // Defer cleanup to avoid cancelling the subscription mid-callback.
            guard state.isInstallable else {
                Task { @MainActor [weak self] in
                    self?.installCancellable = nil
                }
                return
            }

            // Continue the yes chain.
            state.confirm()
        }
    }

    /// Check for updates. Typically connected to a menu item action.
    @objc func checkForUpdates() {
        if viewModel.state == .idle {
            updater.checkForUpdates()
            return
        }

        // Cancel any prior state before re-checking.
        installCancellable?.cancel()
        viewModel.state.cancel()

        // Delay to let the cancellation settle.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            self?.updater.checkForUpdates()
        }
    }

    /// Validate the check for updates menu item.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(checkForUpdates) {
            return updater.canCheckForUpdates
        }
        return true
    }
}
