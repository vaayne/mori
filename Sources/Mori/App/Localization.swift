import Foundation

extension String {
    /// Localized string from this module's bundle, respecting the user's language preference.
    static func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: Bundle.localizedModule)
    }
}

extension Bundle {
    /// Returns a localized sub-bundle of `.module` that respects `AppleLanguages` UserDefaults.
    /// SPM's `Bundle.module` doesn't always pick up `AppleLanguages` overrides,
    /// so we manually resolve the preferred `.lproj` directory.
    static var localizedModule: Bundle {
        let preferred = UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first ?? "en"
        // Try exact match first (e.g. "zh-Hans"), then prefix match (e.g. "zh-Hans-US" -> "zh-Hans")
        let candidates = [preferred] + (preferred.contains("-") ? [String(preferred.prefix(while: { $0 != "-" }))] : [])
        for candidate in candidates {
            if let path = Bundle.module.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        // Fall back to en or module itself
        if let path = Bundle.module.path(forResource: "en", ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .module
    }
}
