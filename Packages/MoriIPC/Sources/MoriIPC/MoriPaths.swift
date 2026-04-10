import Foundation

/// Centralized path resolution for Mori app support directories and IPC socket.
///
/// Resolution order:
/// 1. `MORI_SOCKET_PATH` - explicit socket path override (for testing/CI)
/// 2. `MORI_APP_SUPPORT_DIR` - explicit app support directory override
/// 3. Auto-detect based on bundle type:
///    - Bundled app → `~/Library/Application Support/Mori`
///    - Dev build (swift run, .build-cli) → `~/Library/Application Support/Mori-Dev`
public enum MoriPaths {
    
    // MARK: - Environment Variable Keys
    
    private static let socketPathEnvKey = "MORI_SOCKET_PATH"
    private static let appSupportDirEnvKey = "MORI_APP_SUPPORT_DIR"
    
    // MARK: - Directory Names
    
    private static let productionDirName = "Mori"
    private static let devDirName = "Mori-Dev"
    
    // MARK: - Public API
    
    /// The full path to the IPC socket file.
    /// Uses `MORI_SOCKET_PATH` env var if set, otherwise derives from app support directory.
    public static var socketPath: String {
        // 1. Check explicit socket path override first
        if let envSocketPath = ProcessInfo.processInfo.environment[socketPathEnvKey],
           !envSocketPath.isEmpty {
            return envSocketPath
        }
        
        // 2. Derive from app support directory
        return appSupportDirectory.appendingPathComponent("mori.sock").path
    }
    
    /// The URL to the app support directory.
    /// Uses `MORI_APP_SUPPORT_DIR` env var if set, otherwise auto-detects based on bundle type.
    public static var appSupportDirectory: URL {
        // 1. Check explicit directory override
        if let envDirPath = ProcessInfo.processInfo.environment[appSupportDirEnvKey],
           !envDirPath.isEmpty {
            return URL(fileURLWithPath: envDirPath)
        }
        
        // 2. Auto-detect based on bundle type
        let dirName = isBundledApp ? productionDirName : devDirName
        
        guard let baseDir = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            fatalError("[MoriPaths] Could not resolve Application Support directory")
        }
        return baseDir.appendingPathComponent(dirName, isDirectory: true)
    }
    
    /// Ensures the app support directory exists, creating it if necessary.
    /// - Throws: FileManager errors if directory creation fails.
    public static func ensureAppSupportDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: appSupportDirectory,
            withIntermediateDirectories: true
        )
    }
    
    /// Returns a file URL within the app support directory.
    /// - Parameter filename: The name of the file.
    /// - Returns: A file URL pointing to the file within the app support directory.
    public static func fileURL(for filename: String) -> URL {
        appSupportDirectory.appendingPathComponent(filename)
    }
    
    // MARK: - Private Helpers
    
    /// Detects if running as a bundled macOS app vs a development build.
    ///
    /// For the main app executable, `Bundle.main.bundlePath` returns the `.app` bundle root
    /// (e.g. `/Applications/Mori.app`). But for secondary executables inside the bundle
    /// (e.g. the `mori` CLI at `Contents/MacOS/bin/mori`), `Bundle.main.bundlePath`
    /// returns the directory containing that executable — which does NOT end with `.app`.
    ///
    /// We therefore check the executable's path, walking up to find a `.app` ancestor,
    /// which correctly identifies both the main app and any CLI tools shipped inside it.
    ///
    /// Dev build characteristics (returned as `false`):
    /// - Running via `swift run` (in `.build` directory)
    /// - Running from `.build-cli` directory
    /// - Running from Xcode `DerivedData`
    private static var isBundledApp: Bool {
        // Try Bundle.main first — works for the main app executable
        let bundlePath = Bundle.main.bundlePath
        if bundlePath.hasSuffix(".app") && !isInBuildDirectory(bundlePath) {
            return true
        }

        // Walk up from the executable path to find a .app ancestor.
        // This catches the CLI binary at Contents/MacOS/bin/mori where
        // Bundle.main.bundlePath does NOT point to the .app bundle.
        let execPath: String
        if let mainExec = Bundle.main.executablePath {
            execPath = mainExec
        } else {
            execPath = CommandLine.arguments[0]
        }
        let resolvedExec = URL(fileURLWithPath: execPath).resolvingSymlinksInPath().path

        return isInAppBundle(resolvedExec)
    }

    /// Walk up the directory tree looking for a `.app` ancestor directory.
    static func isInAppBundle(_ path: String) -> Bool {
        var dir = path
        while true {
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir { break } // reached filesystem root
            dir = parent
            if dir.hasSuffix(".app") && !isInBuildDirectory(dir) {
                return true
            }
        }
        return false
    }

    /// Checks whether a path is inside a known build-output directory,
    /// using path-segment matching to avoid false positives on user paths
    /// like `/Users/DerivedDataUser/`.
    static func isInBuildDirectory(_ path: String) -> Bool {
        let buildIndicators = ["/.build/", "/.build-cli/", "/DerivedData/"]
        for indicator in buildIndicators {
            if path.contains(indicator) {
                return true
            }
        }
        return false
    }
}
