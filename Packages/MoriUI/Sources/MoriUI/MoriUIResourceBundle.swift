import Foundation

enum MoriUIResourceBundle {
    private static let bundleName = "MoriUI_MoriUI.bundle"

    static let resourceBundle: Bundle? = {
        for url in candidateBundleURLs() {
            if let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return nil
    }()

    private static func candidateBundleURLs() -> [URL] {
        let baseURLs = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle.main.executableURL?.deletingLastPathComponent(),
        ]

        var seenPaths = Set<String>()
        var urls: [URL] = []

        for baseURL in baseURLs.compactMap({ $0 }) {
            let bundleURL = baseURL.appendingPathComponent(bundleName, isDirectory: true)
            if seenPaths.insert(bundleURL.path).inserted {
                urls.append(bundleURL)
            }
        }

        return urls
    }
}
