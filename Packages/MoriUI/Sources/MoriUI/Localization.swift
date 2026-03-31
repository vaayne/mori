import Foundation

private let moriSharedSuite = "com.vaayne.mori.shared"
private let moriLanguageKey = "MoriLanguage"

extension String {
    static func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .preferredLocalization)
    }

    /// Read the current Mori language preference.
    /// Checks shared suite first, then falls back to system locale.
    static var moriLanguage: String {
        if let lang = UserDefaults(suiteName: moriSharedSuite)?.string(forKey: moriLanguageKey) {
            return lang
        }
        // Fall back to system locale so first-run respects macOS language
        let system = Locale.preferredLanguages.first ?? "en"
        return system.lowercased().hasPrefix("zh") ? "zh-Hans" : "en"
    }

    /// Write the Mori language preference to both shared suite and process defaults.
    static func setMoriLanguage(_ locale: String) {
        UserDefaults(suiteName: moriSharedSuite)?.set(locale, forKey: moriLanguageKey)
        // Also set AppleLanguages so SwiftUI auto-localized Text() and AppKit pick it up
        UserDefaults.standard.set([locale], forKey: "AppleLanguages")
    }
}

private extension Bundle {
    static let preferredLocalization: Bundle = {
        let lproj = String.moriLanguage.lowercased().hasPrefix("zh") ? "zh-hans" : "en"
        if let path = MoriUIResourceBundle.resourceBundle?.path(forResource: lproj, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return MoriUIResourceBundle.resourceBundle ?? .main
    }()
}
