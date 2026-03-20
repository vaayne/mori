import Foundation

extension String {
    /// Localized string from this module's bundle, respecting the user's language preference.
    static func localized(_ key: String.LocalizationValue) -> String {
        // Use String(localized:) with the resolved bundle — this handles interpolation
        // placeholders (%@, %lld) from String.LocalizationValue correctly.
        String(localized: key, bundle: Bundle.localizedModule)
    }
}

extension Bundle {
    /// Returns a localized sub-bundle of `.module` that respects `AppleLanguages` UserDefaults.
    /// SPM lowercases .lproj directory names (e.g. "zh-Hans" → "zh-hans"),
    /// so we scan the bundle directory for case-insensitive matches.
    static var localizedModule: Bundle {
        let preferred = UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first ?? "en"
        // Build candidates: exact, then progressively shorter prefixes
        // e.g. "zh-Hans-US" → ["zh-Hans-US", "zh-Hans", "zh"]
        var candidates = [preferred.lowercased()]
        var remaining = preferred
        while let dashRange = remaining.lastIndex(of: "-") {
            remaining = String(remaining[remaining.startIndex..<dashRange])
            candidates.append(remaining.lowercased())
        }

        // Scan bundle directory for .lproj folders
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
        // Fall back to en
        for dir in lprojDirs {
            if dir.lowercased() == "en.lproj", let bundle = Bundle(path: "\(bundlePath)/\(dir)") {
                return bundle
            }
        }
        return .module
    }
}
