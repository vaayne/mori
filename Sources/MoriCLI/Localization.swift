import Foundation

extension String {
    static func localized(_ key: String.LocalizationValue) -> String {
        guard let bundle = Bundle.preferredLocalization else {
            // Resource bundle unavailable (e.g. CLI inside .app bundle) — return key text
            return String(localized: key)
        }
        return String(localized: key, bundle: bundle)
    }
}

private extension Bundle {
    /// Safely locate the MoriCLI resource bundle without calling Bundle.module
    /// (which fatalErrors when the bundle isn't at the expected SPM path).
    static let safeModule: Bundle? = {
        let bundleName = "Mori_MoriCLI.bundle"

        // 1. Executable-relative (works when bundle is next to the binary)
        let execDir = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
        if let b = Bundle(path: execDir.appendingPathComponent(bundleName).path) {
            return b
        }

        // 2. App bundle Contents/Resources/ (standard macOS app layout)
        if let resourceURL = Bundle.main.resourceURL,
           let b = Bundle(path: resourceURL.appendingPathComponent(bundleName).path) {
            return b
        }

        // 3. Adjacent to main bundle URL (SPM default for CLI tools)
        let mainPath = Bundle.main.bundleURL.appendingPathComponent(bundleName).path
        if let b = Bundle(path: mainPath) {
            return b
        }

        return nil
    }()

    static let preferredLocalization: Bundle? = {
        guard let moduleBundle = safeModule else { return nil }

        let lang: String
        if let stored = UserDefaults(suiteName: "com.vaayne.mori.shared")?.string(forKey: "MoriLanguage") {
            lang = stored
        } else {
            let system = Locale.preferredLanguages.first ?? "en"
            lang = system.lowercased().hasPrefix("zh") ? "zh-Hans" : "en"
        }
        let lproj = lang.lowercased().hasPrefix("zh") ? "zh-hans" : "en"
        if let path = moduleBundle.path(forResource: lproj, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return moduleBundle
    }()
}
