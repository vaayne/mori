import Foundation

extension String {
    /// Localized string from this module's bundle.
    static func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}
