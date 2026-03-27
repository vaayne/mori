// MARK: - UpdateState
// State enum for the Sparkle auto-update system.

import Foundation
@preconcurrency import Sparkle

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

        var releaseNotes: ReleaseNotes? {
            ReleaseNotes(displayVersionString: appcastItem.displayVersionString)
        }
    }

    struct NotFound {
        let acknowledgement: () -> Void
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
    }

    struct Extracting {
        let progress: Double
    }

    struct Installing {
        /// True if triggered by `updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:)`
        var isAutoUpdate = false
        let retryTerminatingApplication: () -> Void
        let dismiss: () -> Void
    }

    // MARK: - Release Notes

    enum ReleaseNotes {
        case tagged(URL)

        init?(displayVersionString: String) {
            let version = displayVersionString

            // Check for semantic version (x.y.z)
            guard let semver = Self.extractSemanticVersion(from: version) else {
                return nil
            }

            guard let url = URL(string: "https://github.com/vaayne/mori/releases/tag/v\(semver)") else {
                return nil
            }

            self = .tagged(url)
        }

        private static func extractSemanticVersion(from version: String) -> String? {
            let pattern = #"^\d+\.\d+\.\d+$"#
            if version.range(of: pattern, options: .regularExpression) != nil {
                return version
            }
            return nil
        }

        var url: URL {
            switch self {
            case .tagged(let url): return url
            }
        }

        var label: String {
            switch self {
            case .tagged: return .localized("View Release Notes")
            }
        }
    }
}
