import Foundation

private let moriSharedSuite = "dev.mori.shared"
private let moriLanguageKey = "MoriLanguage"

extension String {
    static func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .preferredLocalization)
    }

    /// Read the current Mori language preference from the shared suite.
    static var moriLanguage: String {
        UserDefaults(suiteName: moriSharedSuite)?.string(forKey: moriLanguageKey) ?? "en"
    }

    /// Write the Mori language preference to the shared suite.
    static func setMoriLanguage(_ locale: String) {
        UserDefaults(suiteName: moriSharedSuite)?.set(locale, forKey: moriLanguageKey)
    }
}

private extension Bundle {
    static let preferredLocalization: Bundle = {
        let lproj = String.moriLanguage.lowercased().hasPrefix("zh") ? "zh-hans" : "en"
        if let path = Bundle.module.path(forResource: lproj, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .module
    }()
}
