import Foundation

extension String {
    /// Localized string from this module's bundle, respecting the user's language preference.
    static func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: Bundle.localizedModule)
    }
}

extension Bundle {
    /// Returns a localized sub-bundle of `.module` that respects `AppleLanguages` UserDefaults.
    static var localizedModule: Bundle {
        let preferred = UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first ?? "en"
        var candidates = [preferred.lowercased()]
        var remaining = preferred
        while let dashRange = remaining.lastIndex(of: "-") {
            remaining = String(remaining[remaining.startIndex..<dashRange])
            candidates.append(remaining.lowercased())
        }

        let bundlePath = Bundle.module.bundlePath
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: bundlePath) else {
            return .module
        }
        let lprojDirs = contents.filter { $0.hasSuffix(".lproj") }

        for candidate in candidates {
            for dir in lprojDirs {
                let dirName = dir.replacingOccurrences(of: ".lproj", with: "").lowercased()
                if dirName == candidate, let bundle = Bundle(path: "\(bundlePath)/\(dir)") {
                    return bundle
                }
            }
        }
        for dir in lprojDirs {
            if dir.lowercased() == "en.lproj", let bundle = Bundle(path: "\(bundlePath)/\(dir)") {
                return bundle
            }
        }
        return .module
    }
}
