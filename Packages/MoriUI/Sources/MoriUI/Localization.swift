import Foundation

nonisolated(unsafe) let moriLanguageDefaults = UserDefaults(suiteName: "dev.mori.shared")!
private let moriLanguageKey = "MoriLanguage"

extension String {
    static func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .preferredLocalization)
    }
}

private extension Bundle {
    static let preferredLocalization: Bundle = {
        let lang = moriLanguageDefaults.string(forKey: moriLanguageKey) ?? "en"
        let lproj = lang.lowercased().hasPrefix("zh") ? "zh-hans" : "en"
        if let path = Bundle.module.path(forResource: lproj, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .module
    }()
}
