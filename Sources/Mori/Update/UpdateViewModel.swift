// MARK: - UpdateViewModel
// Observable state holder for the update system.
// Uses ObservableObject (not @Observable) for Combine $state.sink support.

import Foundation
import SwiftUI
@preconcurrency import Sparkle

final class UpdateViewModel: ObservableObject {
    @Published var state: UpdateState = .idle

    /// The text to display for the current update state.
    var text: String {
        switch state {
        case .idle:
            return ""
        case .permissionRequest:
            return .localized("Enable Automatic Updates?")
        case .checking:
            return .localized("Checking for updates\u{2026}")
        case .updateAvailable(let update):
            let version = update.appcastItem.displayVersionString
            if !version.isEmpty {
                return String(format: .localized("Update Available: %@"), version)
            }
            return .localized("Update Available")
        case .downloading(let download):
            if let expectedLength = download.expectedLength, expectedLength > 0 {
                let progress = Double(download.progress) / Double(expectedLength)
                return String(format: .localized("Downloading: %.0f%%"), progress * 100)
            }
            return .localized("Downloading\u{2026}")
        case .extracting(let extracting):
            return String(format: .localized("Preparing: %.0f%%"), extracting.progress * 100)
        case .installing(let install):
            return install.isAutoUpdate ? .localized("Restart to Complete Update") : .localized("Installing\u{2026}")
        case .notFound:
            return .localized("No Updates Available")
        case .error(let err):
            return err.error.localizedDescription
        }
    }

    /// The maximum width text for states that show progress.
    /// Used to prevent the pill from resizing as percentages change.
    var maxWidthText: String {
        switch state {
        case .downloading:
            return .localized("Downloading: 100%%")
        case .extracting:
            return .localized("Preparing: 100%%")
        default:
            return text
        }
    }

    /// The SF Symbol icon name for the current update state.
    var iconName: String? {
        switch state {
        case .idle:
            return nil
        case .permissionRequest:
            return "questionmark.circle"
        case .checking:
            return "arrow.triangle.2.circlepath"
        case .updateAvailable:
            return "shippingbox.fill"
        case .downloading:
            return "arrow.down.circle"
        case .extracting:
            return "shippingbox"
        case .installing:
            return "power.circle"
        case .notFound:
            return "info.circle"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    /// A longer description for the current update state.
    var description: String {
        switch state {
        case .idle:
            return ""
        case .permissionRequest:
            return .localized("Configure automatic update preferences")
        case .checking:
            return .localized("Please wait while we check for available updates")
        case .updateAvailable(let update):
            return update.releaseNotesURL != nil ? .localized("View Release Notes") : .localized("Download and install the latest version")
        case .downloading:
            return .localized("Downloading the update package")
        case .extracting:
            return .localized("Extracting and preparing the update")
        case .installing(let install):
            return install.isAutoUpdate ? .localized("Restart to Complete Update") : .localized("Installing update and preparing to restart")
        case .notFound:
            return .localized("You are running the latest version")
        case .error:
            return .localized("An error occurred during the update process")
        }
    }

    /// A badge to display for the current update state.
    var badge: String? {
        switch state {
        case .updateAvailable(let update):
            let version = update.appcastItem.displayVersionString
            return version.isEmpty ? nil : version
        case .downloading(let download):
            if let expectedLength = download.expectedLength, expectedLength > 0 {
                let percentage = Double(download.progress) / Double(expectedLength) * 100
                return String(format: "%.0f%%", percentage)
            }
            return nil
        case .extracting(let extracting):
            return String(format: "%.0f%%", extracting.progress * 100)
        default:
            return nil
        }
    }

    /// The color to apply to the icon for the current update state.
    var iconColor: Color {
        switch state {
        case .idle:
            return .secondary
        case .permissionRequest:
            return .white
        case .checking:
            return .secondary
        case .updateAvailable:
            return .accentColor
        case .downloading, .extracting, .installing:
            return .secondary
        case .notFound:
            return .secondary
        case .error:
            return .orange
        }
    }

    /// The background color for the update pill.
    var backgroundColor: Color {
        switch state {
        case .permissionRequest:
            return Color(nsColor: NSColor.systemBlue.blended(withFraction: 0.3, of: .black) ?? .systemBlue)
        case .updateAvailable:
            return .accentColor
        case .notFound:
            return Color(nsColor: NSColor.systemBlue.blended(withFraction: 0.5, of: .black) ?? .systemBlue)
        case .error:
            return .orange.opacity(0.2)
        default:
            return Color(nsColor: .controlBackgroundColor)
        }
    }

    /// The foreground (text) color for the update pill.
    var foregroundColor: Color {
        switch state {
        case .permissionRequest:
            return .white
        case .updateAvailable:
            return .white
        case .notFound:
            return .white
        case .error:
            return .orange
        default:
            return .primary
        }
    }
}
