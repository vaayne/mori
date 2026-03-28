// MARK: - UpdateState
// State enum for the Sparkle auto-update system.

import Foundation
@preconcurrency import Sparkle

private let gitHubReleasesBase = "https://github.com/vaayne/mori/releases/tag/v"

/// Represents the current state of the update lifecycle.
enum UpdateState: Equatable {
    case idle
    case permissionRequest(PermissionRequest)
    case checking(Checking)
    case updateAvailable(UpdateAvailable)
    case downloading(Downloading)
    case extracting(Extracting)
    case installing(Installing)
    case notFound(NotFound)
    case error(Error)

    // MARK: - Helpers

    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }

    /// True if we're in a state that can be force installed.
    var isInstallable: Bool {
        switch self {
        case .checking,
             .updateAvailable,
             .downloading,
             .extracting,
             .installing:
            return true
        default:
            return false
        }
    }

    func cancel() {
        switch self {
        case .checking(let checking):
            checking.cancel()
        case .updateAvailable(let available):
            available.reply(.dismiss)
        case .downloading(let downloading):
            downloading.cancel()
        case .notFound(let notFound):
            notFound.acknowledgement()
        case .error(let err):
            err.dismiss()
        default:
            break
        }
    }

    /// Confirms or accepts the current update state.
    /// - For available updates: begins installation
    func confirm() {
        switch self {
        case .updateAvailable(let available):
            available.reply(.install)
        default:
            break
        }
    }

    // MARK: - Equatable

    static func == (lhs: UpdateState, rhs: UpdateState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.permissionRequest, .permissionRequest):
            return true
        case (.checking, .checking):
            return true
        case (.updateAvailable(let lUpdate), .updateAvailable(let rUpdate)):
            return lUpdate.appcastItem.displayVersionString == rUpdate.appcastItem.displayVersionString
        case (.notFound, .notFound):
            return true
        case (.error(let lErr), .error(let rErr)):
            return lErr.error.localizedDescription == rErr.error.localizedDescription
        case (.downloading(let lDown), .downloading(let rDown)):
            return lDown.progress == rDown.progress && lDown.expectedLength == rDown.expectedLength
        case (.extracting(let lExt), .extracting(let rExt)):
            return lExt.progress == rExt.progress
        case (.installing(let lInstall), .installing(let rInstall)):
            return lInstall.isAutoUpdate == rInstall.isAutoUpdate
        default:
            return false
        }
    }

    // MARK: - Associated Types

    struct PermissionRequest {
        let request: SPUUpdatePermissionRequest
        let reply: @Sendable (SUUpdatePermissionResponse) -> Void
    }

    struct Checking {
        let cancel: () -> Void
    }

    struct UpdateAvailable {
        let appcastItem: SUAppcastItem
        let reply: @Sendable (SPUUserUpdateChoice) -> Void

        /// URL to the GitHub release page for this version, if the version is semver.
        var releaseNotesURL: URL? {
            let version = appcastItem.displayVersionString
            let pattern = #"^\d+\.\d+\.\d+$"#
            guard version.range(of: pattern, options: .regularExpression) != nil else { return nil }
            return URL(string: "\(gitHubReleasesBase)\(version)")
        }
    }

    struct NotFound {
        let acknowledgement: () -> Void

        /// Acknowledge and transition back to idle. Safe to call multiple times via `callOnce` on construction.
        func dismiss(from model: UpdateViewModel) {
            model.state = .idle
            acknowledgement()
        }
    }

    struct Error {
        let error: any Swift.Error
        let retry: () -> Void
        let dismiss: () -> Void
    }

    struct Downloading {
        let cancel: () -> Void
        let expectedLength: UInt64?
        let progress: UInt64

        /// Download progress normalized to 0.0–1.0, or nil if expected length is unknown.
        var normalizedProgress: Double? {
            guard let expectedLength, expectedLength > 0 else { return nil }
            return min(1, max(0, Double(progress) / Double(expectedLength)))
        }
    }

    struct Extracting {
        let progress: Double

        /// Extraction progress clamped to 0.0–1.0.
        var normalizedProgress: Double {
            min(1, max(0, progress))
        }
    }

    struct Installing {
        /// True when triggered by `updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:)`.
        /// The driver sets this to `true` for auto-updates (delegate path) and defaults to
        /// `false` for user-initiated installs (showInstallingUpdate path).
        var isAutoUpdate = false
        let retryTerminatingApplication: () -> Void
        let dismiss: () -> Void
    }
}
