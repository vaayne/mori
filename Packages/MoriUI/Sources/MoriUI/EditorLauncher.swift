import AppKit

/// Detected external editor with launch capability.
public struct ExternalEditor: Identifiable, Sendable {
    public let id: String          // bundle identifier
    public let name: String
    public let bundleId: String
    public let icon: String        // SF Symbol name

    /// Open a path in this editor.
    public func open(path: String) {
        let url = URL(fileURLWithPath: path)
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: appURL,
                configuration: NSWorkspace.OpenConfiguration()
            )
        }
    }
}

/// Detects installed code editors on macOS.
@MainActor
public enum EditorLauncher {

    private static let knownEditors: [(bundleId: String, name: String, icon: String)] = [
        ("dev.zed.Zed", "Zed", "curlybraces"),
        ("com.microsoft.VSCode", "VS Code", "chevron.left.forwardslash.chevron.right"),
        ("com.sublimetext.4", "Sublime Text", "text.cursor"),
        ("com.jetbrains.intellij", "IntelliJ IDEA", "hammer"),
        ("com.apple.dt.Xcode", "Xcode", "wrench.and.screwdriver"),
        ("com.todesktop.230313mzl4w4u92", "Cursor", "cursorarrow.rays"),
    ]

    /// Returns editors that are currently installed on the system.
    /// Result is cached after first call.
    public static var installed: [ExternalEditor] {
        if let cached = _cached { return cached }
        let result = knownEditors.compactMap { entry -> ExternalEditor? in
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleId) != nil else {
                return nil
            }
            return ExternalEditor(
                id: entry.bundleId,
                name: entry.name,
                bundleId: entry.bundleId,
                icon: entry.icon
            )
        }
        _cached = result
        return result
    }

    private static var _cached: [ExternalEditor]?
}
