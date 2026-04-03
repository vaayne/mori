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
    /// Bundled app characteristics:
    /// - Bundle path ends with `.app`
    /// - Not located in `.build` or `DerivedData` directories
    ///
    /// Dev build characteristics:
    /// - Running via `swift run` (in `.build` directory)
    /// - Running from `.build-cli` directory
    /// - Running from Xcode `DerivedData`
    private static var isBundledApp: Bool {
        let bundlePath = Bundle.main.bundlePath
        
        // Must end with .app to be considered a bundled app
        guard bundlePath.hasSuffix(".app") else {
            return false
        }
        
        // Must NOT be in build directories (use path-segment matching to avoid
        // false positives on user paths like /Users/DerivedDataUser/)
        let buildIndicators = ["/.build/", "/.build-cli/", "/DerivedData/"]
        for indicator in buildIndicators {
            if bundlePath.contains(indicator) {
                return false
            }
        }
        
        return true
    }
}
