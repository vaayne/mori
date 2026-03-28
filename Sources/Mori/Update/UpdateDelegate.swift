// MARK: - UpdateDelegate
// SPUUpdaterDelegate conformance providing install hooks.
// Feed URL is read from SUFeedURL in Info.plist (set by bundle.sh).

import Cocoa
@preconcurrency import Sparkle

extension UpdateDriver: SPUUpdaterDelegate {

    /// Called when an update is scheduled to install silently on quit.
    func updater(_ updater: SPUUpdater,
                 willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        viewModel.state = .installing(.init(
            isAutoUpdate: true,
            retryTerminatingApplication: immediateInstallHandler,
            dismiss: { [weak viewModel] in
                viewModel?.state = .idle
            }
        ))
        return true
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        // Invalidate restorable state so macOS re-encodes it before relaunch.
        NSApp.invalidateRestorableState()
        for window in NSApp.windows { window.invalidateRestorableState() }
    }
}
