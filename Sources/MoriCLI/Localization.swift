import Foundation

extension String {
    static func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .preferredLocalization)
    }
}

private extension Bundle {
    static let preferredLocalization: Bundle = {
        let preferred = UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first ?? "en"
        let lang = preferred.lowercased().hasPrefix("zh") ? "zh-hans" : "en"
        if let path = Bundle.module.path(forResource: lang, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .module
    }()
}
