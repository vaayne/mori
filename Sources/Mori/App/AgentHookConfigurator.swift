import Foundation

/// Installs and uninstalls Mori agent hook scripts for coding agents.
/// Writes hook scripts to $XDG_CONFIG_HOME/mori/hooks/ (fallback: ~/.config/mori/hooks/)
/// and merges/removes hook entries in agent config files.
///
/// Hook script sources live in Sources/Mori/Resources/ and are embedded via SPM bundle resources.
enum AgentHookConfigurator {

    /// Display names for notifications, keyed by agent process name.
    static let agentDisplayNames: [String: String] = [
        "claude": "Claude Code",
        "codex": "Codex",
        "pi": "Pi",
        "droid": "Droid",
    ]

    /// Claude Code hook event names (used for both install and uninstall).
    private static let claudeEvents = ["UserPromptSubmit", "Stop", "Notification"]

    /// Droid hook event names (same lifecycle events as Claude Code).
    private static let droidEvents = ["UserPromptSubmit", "Stop", "Notification"]

    private static let home = FileManager.default.homeDirectoryForCurrentUser

    /// Mori config directory: $XDG_CONFIG_HOME/mori or ~/.config/mori
    private static var configDir: URL {
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg).appendingPathComponent("mori")
        }
        return home.appendingPathComponent(".config/mori")
    }

    private static var hooksDir: URL {
        configDir.appendingPathComponent("hooks")
    }

    private static var claudeHookPath: String {
        hooksDir.appendingPathComponent("mori-agent-hook.sh").path
    }

    private static var codexHookPath: String {
        hooksDir.appendingPathComponent("mori-codex-hook.sh").path
    }

    private static var droidHookPath: String {
        hooksDir.appendingPathComponent("mori-droid-hook.sh").path
    }

    /// Factory (Droid) settings: ~/.factory/settings.json
    private static var factorySettingsURL: URL {
        home.appendingPathComponent(".factory/settings.json")
    }

    /// Pi config directory: $PI_CODING_AGENT_DIR or ~/.pi/agent
    private static var piAgentDir: URL {
        if let dir = ProcessInfo.processInfo.environment["PI_CODING_AGENT_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir)
        }
        return home.appendingPathComponent(".pi/agent")
    }

    private static var piExtensionURL: URL {
        configDir.appendingPathComponent("mori-pi-extension.ts")
    }

    // MARK: - Detection

    /// Refresh any agent hooks/extensions that are currently registered in user config.
    /// This keeps the files under ~/.config/mori/ aligned with the current Mori bundle
    /// on every launch, without enabling hooks for agents the user never turned on.
    static func refreshInstalledHooks() {
        if isClaudeHookInstalled() {
            installClaudeHook()
        }
        if isCodexHookInstalled() {
            installCodexHook()
        }
        if isDroidHookInstalled() {
            installDroidHook()
        }
        if piSettingsContainsExtension() {
            installPiExtension()
        }
    }

    /// Check if Claude Code hooks are installed in ~/.claude/settings.json.
    static func isClaudeHookInstalled() -> Bool {
        let settingsURL = home.appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else { return false }
        return hookEntryExists(in: hooks, event: "Stop", command: "\(claudeHookPath) Stop")
    }

    /// Check if Codex CLI hook is installed in ~/.codex/config.toml.
    static func isCodexHookInstalled() -> Bool {
        let configURL = home.appendingPathComponent(".codex/config.toml")
        guard let content = try? String(contentsOf: configURL, encoding: .utf8) else { return false }
        return content.contains(codexHookPath)
    }

    /// Check if Droid hooks are installed in ~/.factory/settings.json.
    static func isDroidHookInstalled() -> Bool {
        guard let data = try? Data(contentsOf: factorySettingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else { return false }
        return hookEntryExists(in: hooks, event: "Stop", command: "\(droidHookPath) Stop")
    }

    /// Check if Pi extension is installed and registered in ~/.pi/agent/settings.json.
    static func isPiExtensionInstalled() -> Bool {
        guard FileManager.default.fileExists(atPath: piExtensionURL.path) else { return false }
        return piSettingsContainsExtension()
    }

    // MARK: - Install

    /// Ensure the shared hook library is installed (sourced by agent-specific scripts).
    private static func installCommonScript() {
        guard let source = loadBundledResource("mori-hook-common", ext: "sh") else { return }
        installScript(name: "mori-hook-common", source: source)
    }

    /// Install Claude Code hook only.
    static func installClaudeHook() {
        ensureHooksDir()
        installCommonScript()
        guard let source = loadBundledResource("mori-agent-hook", ext: "sh"),
              let path = installScript(name: "mori-agent-hook", source: source) else { return }
        configureClaudeSettings(hookPath: path)
    }

    /// Install Codex CLI hook only.
    static func installCodexHook() {
        ensureHooksDir()
        installCommonScript()
        guard let source = loadBundledResource("mori-codex-hook", ext: "sh"),
              let path = installScript(name: "mori-codex-hook", source: source) else { return }
        configureCodexSettings(hookPath: path)
    }

    /// Install Droid hook and register in ~/.factory/settings.json.
    static func installDroidHook() {
        ensureHooksDir()
        installCommonScript()
        guard let source = loadBundledResource("mori-droid-hook", ext: "sh"),
              let path = installScript(name: "mori-droid-hook", source: source) else { return }
        configureDroidSettings(hookPath: path)
    }

    /// Install Pi extension to mori config dir and register in Pi's settings.json.
    static func installPiExtension() {
        guard let source = loadBundledResource("mori-pi-extension", ext: "ts") else { return }
        ensureConfigDir()
        installFile(at: piExtensionURL, content: source)
        registerPiExtension()
    }

    // MARK: - Uninstall

    /// Remove Claude Code hooks from ~/.claude/settings.json and delete hook script.
    static func uninstallClaudeHook() {
        let settingsURL = home.appendingPathComponent(".claude/settings.json")
        if let data = try? Data(contentsOf: settingsURL),
           var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           var hooks = json["hooks"] as? [String: Any] {
            var changed = false
            for event in claudeEvents {
                let command = "\(claudeHookPath) \(event)"
                if removeHookEntry(from: &hooks, event: event, command: command) {
                    changed = true
                }
            }
            if changed {
                for (key, value) in hooks {
                    if let arr = value as? [[String: Any]], arr.isEmpty {
                        hooks.removeValue(forKey: key)
                    }
                }
                if hooks.isEmpty {
                    json.removeValue(forKey: "hooks")
                } else {
                    json["hooks"] = hooks
                }
                writeJSON(json, to: settingsURL)
            }
        }
        try? FileManager.default.removeItem(atPath: claudeHookPath)
    }

    /// Remove Codex CLI hook from ~/.codex/config.toml and delete hook script.
    static func uninstallCodexHook() {
        let configURL = home.appendingPathComponent(".codex/config.toml")
        if let content = try? String(contentsOf: configURL, encoding: .utf8),
           content.contains(codexHookPath) {
            var lines = content.components(separatedBy: "\n")
            if let idx = lines.firstIndex(where: { $0.hasPrefix("notify") && $0.contains(codexHookPath) }) {
                var entries = parseTomlStringArray(lines[idx])
                entries.removeAll { $0 == codexHookPath }
                if entries.isEmpty {
                    // Remove the notify line and the comment above it
                    lines.remove(at: idx)
                    if idx > 0 && lines[idx - 1] == "# Mori agent status hook" {
                        lines.remove(at: idx - 1)
                    }
                } else {
                    lines[idx] = "notify = [\(entries.map { "\"\($0)\"" }.joined(separator: ", "))]"
                }
            }
            let cleaned = lines.joined(separator: "\n")
            try? cleaned.write(to: configURL, atomically: true, encoding: .utf8)
        }
        try? FileManager.default.removeItem(atPath: codexHookPath)
    }

    /// Remove Droid hooks from ~/.factory/settings.json and delete hook script.
    static func uninstallDroidHook() {
        if let data = try? Data(contentsOf: factorySettingsURL),
           var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           var hooks = json["hooks"] as? [String: Any] {
            var changed = false
            for event in droidEvents {
                let command = "\(droidHookPath) \(event)"
                if removeHookEntry(from: &hooks, event: event, command: command) {
                    changed = true
                }
            }
            if changed {
                for (key, value) in hooks {
                    if let arr = value as? [[String: Any]], arr.isEmpty {
                        hooks.removeValue(forKey: key)
                    }
                }
                if hooks.isEmpty {
                    json.removeValue(forKey: "hooks")
                } else {
                    json["hooks"] = hooks
                }
                writeJSON(json, to: factorySettingsURL)
            }
        }
        try? FileManager.default.removeItem(atPath: droidHookPath)
    }

    /// Remove Pi extension file and unregister from settings.json.
    static func uninstallPiExtension() {
        try? FileManager.default.removeItem(at: piExtensionURL)
        unregisterPiExtension()
    }

    // MARK: - Directory Setup

    private static func ensureConfigDir() {
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
    }

    private static func ensureHooksDir() {
        try? FileManager.default.createDirectory(at: hooksDir, withIntermediateDirectories: true)
    }

    // MARK: - Bundle Resources

    /// Load a script from Mori's packaged resource bundle.
    private static func loadBundledResource(_ name: String, ext: String) -> String? {
        guard let url = MoriAppResourceBundle.resourceBundle?.url(forResource: name, withExtension: ext) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Script Installation

    /// Write a hook script to the hooks dir. Returns the installed path, or nil on failure.
    @discardableResult
    private static func installScript(name: String, source: String) -> String? {
        let url = hooksDir.appendingPathComponent(name + ".sh")
        let existing = try? String(contentsOf: url, encoding: .utf8)
        if existing == source { return url.path }
        do {
            try source.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            return url.path
        } catch {
            return nil
        }
    }

    /// Write a non-shell file (e.g. TypeScript extension). Returns the installed path.
    @discardableResult
    private static func installFile(at url: URL, content: String) -> String? {
        let existing = try? String(contentsOf: url, encoding: .utf8)
        if existing == content { return url.path }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url.path
        } catch {
            return nil
        }
    }

    // MARK: - Claude Code

    private static func configureClaudeSettings(hookPath: String) {
        let settingsURL = home.appendingPathComponent(".claude/settings.json")

        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = json
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var changed = false

        for event in claudeEvents {
            let command = "\(hookPath) \(event)"
            if !hookEntryExists(in: hooks, event: event, command: command) {
                let entry: [String: Any] = [
                    "hooks": [["type": "command", "command": command]]
                ]
                var eventHooks = hooks[event] as? [[String: Any]] ?? []
                eventHooks.append(entry)
                hooks[event] = eventHooks
                changed = true
            }
        }

        guard changed else { return }
        settings["hooks"] = hooks
        writeJSON(settings, to: settingsURL)
    }

    // MARK: - Codex CLI

    private static func configureCodexSettings(hookPath: String) {
        let configURL = home.appendingPathComponent(".codex/config.toml")

        let existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""

        if existing.contains(hookPath) { return }

        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        var lines = existing.components(separatedBy: "\n")
        if let idx = lines.firstIndex(where: { $0.hasPrefix("notify") && $0.contains("[") }) {
            // Append to existing notify array, preserving other entries
            let existingLine = lines[idx]
            let entries = parseTomlStringArray(existingLine)
            if !entries.contains(hookPath) {
                var updated = entries
                updated.append(hookPath)
                lines[idx] = "notify = [\(updated.map { "\"\($0)\"" }.joined(separator: ", "))]"
            }
        } else {
            // Insert before the first [section] header to keep it top-level
            let notifyLines = ["# Mori agent status hook", "notify = [\"\(hookPath)\"]", ""]
            if let sectionIdx = lines.firstIndex(where: { $0.hasPrefix("[") }) {
                lines.insert(contentsOf: notifyLines, at: sectionIdx)
            } else {
                if !lines.last!.isEmpty { lines.append("") }
                lines.append(contentsOf: notifyLines)
            }
        }
        let config = lines.joined(separator: "\n")
        try? config.write(to: configURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Droid

    private static func configureDroidSettings(hookPath: String) {
        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: factorySettingsURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = json
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var changed = false

        for event in droidEvents {
            let command = "\(hookPath) \(event)"
            if !hookEntryExists(in: hooks, event: event, command: command) {
                let entry: [String: Any] = [
                    "hooks": [["type": "command", "command": command]]
                ]
                var eventHooks = hooks[event] as? [[String: Any]] ?? []
                eventHooks.append(entry)
                hooks[event] = eventHooks
                changed = true
            }
        }

        guard changed else { return }

        try? FileManager.default.createDirectory(
            at: factorySettingsURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        settings["hooks"] = hooks
        writeJSON(settings, to: factorySettingsURL)
    }

    // MARK: - Pi

    private static var piExtensionSettingsPath: String {
        // Pi settings use ~/relative paths
        let filePath = piExtensionURL.path
        let homePath = home.path
        if filePath.hasPrefix(homePath) {
            return "~" + filePath.dropFirst(homePath.count)
        }
        return filePath
    }

    private static var piSettingsURL: URL {
        piAgentDir.appendingPathComponent("settings.json")
    }

    private static func piSettingsContainsExtension() -> Bool {
        guard let data = try? Data(contentsOf: piSettingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let extensions = json["extensions"] as? [String] else { return false }
        return extensions.contains(piExtensionSettingsPath)
    }

    private static func registerPiExtension() {
        guard let data = try? Data(contentsOf: piSettingsURL),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        var extensions = json["extensions"] as? [String] ?? []
        guard !extensions.contains(piExtensionSettingsPath) else { return }
        extensions.append(piExtensionSettingsPath)
        json["extensions"] = extensions
        writeJSON(json, to: piSettingsURL)
    }

    private static func unregisterPiExtension() {
        guard let data = try? Data(contentsOf: piSettingsURL),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var extensions = json["extensions"] as? [String] else { return }
        extensions.removeAll { $0 == piExtensionSettingsPath }
        json["extensions"] = extensions
        writeJSON(json, to: piSettingsURL)
    }

    // MARK: - Helpers

    private static func hookEntryExists(
        in hooks: [String: Any], event: String, command: String
    ) -> Bool {
        guard let entries = hooks[event] as? [[String: Any]] else { return false }
        for entry in entries {
            guard let hookList = entry["hooks"] as? [[String: Any]] else { continue }
            for hook in hookList where hook["command"] as? String == command { return true }
        }
        return false
    }

    @discardableResult
    private static func removeHookEntry(
        from hooks: inout [String: Any], event: String, command: String
    ) -> Bool {
        guard var entries = hooks[event] as? [[String: Any]] else { return false }
        let originalCount = entries.count
        entries.removeAll { entry in
            guard let hookList = entry["hooks"] as? [[String: Any]] else { return false }
            return hookList.contains { $0["command"] as? String == command }
        }
        guard entries.count != originalCount else { return false }
        hooks[event] = entries
        return true
    }

    private static func writeJSON(_ object: [String: Any], to url: URL) {
        guard let data = try? JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        // `.atomic` uses rename(), which replaces a symlink target with a
        // regular file instead of following it. Resolve first so users whose
        // settings.json is a symlink into a dotfiles repo keep the link intact.
        let resolved = url.resolvingSymlinksInPath()
        try? data.write(to: resolved, options: .atomic)
    }

    /// Parse a TOML string array like `notify = ["/a", "/b"]` into `["/a", "/b"]`.
    private static func parseTomlStringArray(_ line: String) -> [String] {
        guard let open = line.firstIndex(of: "["),
              let close = line.lastIndex(of: "]") else { return [] }
        let inner = line[line.index(after: open)..<close]
        return inner.split(separator: ",").compactMap { segment in
            let trimmed = segment.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") else { return nil }
            return String(trimmed.dropFirst().dropLast())
        }
    }
}
