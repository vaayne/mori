import Foundation

extension String {
    static func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .preferredLocalization)
    }
}

private extension Bundle {
    static let preferredLocalization: Bundle = {
        let lang: String
        if let stored = UserDefaults(suiteName: "com.vaayne.mori.shared")?.string(forKey: "MoriLanguage") {
            lang = stored
        } else {
            let system = Locale.preferredLanguages.first ?? "en"
            lang = system.lowercased().hasPrefix("zh") ? "zh-Hans" : "en"
        }
        let lproj = lang.lowercased().hasPrefix("zh") ? "zh-hans" : "en"
        if let path = MoriAppResourceBundle.resourceBundle?.path(forResource: lproj, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return MoriAppResourceBundle.resourceBundle ?? .main
    }()
}
