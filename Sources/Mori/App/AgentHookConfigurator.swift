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

    /// Removed in 30dca6a; migrate existing Mori registrations without touching other hooks.
    private static let obsoleteToolUseEvent = "PreToolUse"

    /// Codex's low-noise lifecycle events. Tool-level events intentionally remain unregistered.
    private static let codexEvents = ["UserPromptSubmit", "Stop"]

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

    private static var codexHooksURL: URL {
        home.appendingPathComponent(".codex/hooks.json")
    }

    private static var codexConfigURL: URL {
        home.appendingPathComponent(".codex/config.toml")
    }

    /// The default path also recognizes installations created before an XDG override.
    private static var knownCodexHookPaths: Set<String> {
        [
            codexHookPath,
            home.appendingPathComponent(".config/mori/hooks/mori-codex-hook.sh").path,
        ]
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

    /// Check modern hooks.json and the legacy top-level TOML notify registration.
    static func isCodexHookInstalled() -> Bool {
        isModernCodexHookInstalled() || legacyCodexHookInstalled()
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
        // Establish the replacement first. Cross-file migration cannot be atomic, so a
        // temporary duplicate is safer than dropping state reporting on a failed write.
        guard configureCodexHooks(hookPath: path) else { return }
        _ = removeLegacyCodexHookRegistration()
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
            for event in claudeEvents + [obsoleteToolUseEvent] {
                if removeHookCommands(from: &hooks, event: event, commands: ["\(claudeHookPath) \(event)"]) {
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

    /// Remove modern and legacy Codex registrations, then delete the dedicated script.
    static func uninstallCodexHook() {
        guard removeModernCodexHookRegistration(), removeLegacyCodexHookRegistration() else { return }
        try? FileManager.default.removeItem(atPath: codexHookPath)
    }

    /// Remove Droid hooks from ~/.factory/settings.json and delete hook script.
    static func uninstallDroidHook() {
        if let data = try? Data(contentsOf: factorySettingsURL),
           var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           var hooks = json["hooks"] as? [String: Any] {
            var changed = false
            for event in droidEvents + [obsoleteToolUseEvent] {
                if removeHookCommands(from: &hooks, event: event, commands: ["\(droidHookPath) \(event)"]) {
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
        var changed = removeHookCommands(
            from: &hooks,
            event: obsoleteToolUseEvent,
            commands: ["\(hookPath) \(obsoleteToolUseEvent)"]
        )

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

    private static func isModernCodexHookInstalled() -> Bool {
        guard let data = try? Data(contentsOf: codexHooksURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else { return false }
        return codexEvents.contains { event in
            knownCodexHookPaths.contains { path in
                hookEntryExists(in: hooks, event: event, command: "\(path) \(event)")
            }
        }
    }

    private static func legacyCodexHookInstalled() -> Bool {
        guard let content = try? String(contentsOf: codexConfigURL, encoding: .utf8) else { return false }
        return topLevelNotifyEntries(in: content).contains { entry in
            knownCodexHookPaths.contains(entry) || embeddedNotifyContainsMoriHook(entry)
        }
    }

    /// Upsert only Mori's two commands, retaining every other JSON field and hook.
    private static func configureCodexHooks(hookPath: String) -> Bool {
        var settings: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: codexHooksURL.path) {
            guard let data = try? Data(contentsOf: codexHooksURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            settings = json
        } else {
            try? FileManager.default.createDirectory(
                at: codexHooksURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
        }

        var hooks: [String: Any]
        if let existingHooks = settings["hooks"] {
            guard let parsedHooks = existingHooks as? [String: Any] else { return false }
            hooks = parsedHooks
        } else {
            hooks = [:]
        }

        var changed = false
        for event in codexEvents {
            let command = "\(hookPath) \(event)"
            if !hookEntryExists(in: hooks, event: event, command: command) {
                var eventHooks: [[String: Any]]
                if let existingEventHooks = hooks[event] {
                    guard let parsedEventHooks = existingEventHooks as? [[String: Any]] else { return false }
                    eventHooks = parsedEventHooks
                } else {
                    eventHooks = []
                }
                eventHooks.append(["hooks": [["type": "command", "command": command]]])
                hooks[event] = eventHooks
                changed = true
            }
        }

        guard changed else { return true }
        settings["hooks"] = hooks
        return writeJSON(settings, to: codexHooksURL)
    }

    private static func removeModernCodexHookRegistration() -> Bool {
        guard FileManager.default.fileExists(atPath: codexHooksURL.path) else { return true }
        guard let data = try? Data(contentsOf: codexHooksURL),
              var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings["hooks"] == nil }

        var changed = false
        for event in codexEvents {
            if removeHookCommands(from: &hooks, event: event, commands: knownCodexHookPaths.map { "\($0) \(event)" }) {
                changed = true
            }
        }
        guard changed else { return true }
        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }
        return writeJSON(settings, to: codexHooksURL)
    }

    /// Remove only Mori paths from the legacy *top-level* `notify` array.
    /// A conservative parser means unsupported TOML is left untouched rather than rewritten.
    private static func removeLegacyCodexHookRegistration() -> Bool {
        guard let content = try? String(contentsOf: codexConfigURL, encoding: .utf8) else { return true }
        var lines = content.components(separatedBy: "\n")
        var inSection = false
        var changed = false

        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { inSection = true }
            guard !inSection, isTopLevelNotifyLine(trimmed), let entries = parseTomlStringArray(lines[index]) else { continue }

            let updated = entries.compactMap { entry -> String? in
                if knownCodexHookPaths.contains(entry) { return nil }
                guard let payload = entry.data(using: .utf8),
                      var nested = try? JSONSerialization.jsonObject(with: payload) as? [String] else { return entry }
                let originalCount = nested.count
                nested.removeAll { knownCodexHookPaths.contains($0) }
                guard nested.count != originalCount,
                      let encoded = try? JSONSerialization.data(withJSONObject: nested),
                      let value = String(data: encoded, encoding: .utf8) else { return entry }
                return value
            }
            guard updated.count != entries.count || updated != entries else { continue }
            if updated.isEmpty {
                lines.remove(at: index)
                if index > 0,
                   lines[index - 1].trimmingCharacters(in: .whitespaces) == "# Mori agent status hook" {
                    lines.remove(at: index - 1)
                }
            } else {
                guard let encoded = encodeTomlStringArray(updated) else { return false }
                lines[index] = "notify = \(encoded)"
            }
            changed = true
            break // TOML permits one top-level `notify` key.
        }
        return !changed || writeText(lines.joined(separator: "\n"), to: codexConfigURL)
    }

    // MARK: - Droid

    private static func configureDroidSettings(hookPath: String) {
        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: factorySettingsURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = json
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var changed = removeHookCommands(
            from: &hooks,
            event: obsoleteToolUseEvent,
            commands: ["\(hookPath) \(obsoleteToolUseEvent)"]
        )

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
    private static func writeJSON(_ object: [String: Any], to url: URL) -> Bool {
        guard let data = try? JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys]
        ) else { return false }
        // `.atomic` uses rename(), which replaces a symlink target with a
        // regular file instead of following it. Resolve first so users whose
        // settings.json is a symlink into a dotfiles repo keep the link intact.
        let resolved = url.resolvingSymlinksInPath()
        do {
            try data.write(to: resolved, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static func writeText(_ text: String, to url: URL) -> Bool {
        do {
            try text.write(to: url.resolvingSymlinksInPath(), atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    private static func removeHookCommands(
        from hooks: inout [String: Any], event: String, commands: [String]
    ) -> Bool {
        guard var entries = hooks[event] as? [[String: Any]] else { return false }
        var changed = false
        for index in entries.indices.reversed() {
            guard let hookList = entries[index]["hooks"] as? [[String: Any]] else { continue }
            let retained = hookList.filter { hook in
                guard let command = hook["command"] as? String else { return true }
                return !commands.contains(command)
            }
            guard retained.count != hookList.count else { continue }
            changed = true
            if retained.isEmpty {
                entries.remove(at: index)
            } else {
                entries[index]["hooks"] = retained
            }
        }
        guard changed else { return false }
        if entries.isEmpty {
            hooks.removeValue(forKey: event)
        } else {
            hooks[event] = entries
        }
        return true
    }

    private static func topLevelNotifyEntries(in content: String) -> [String] {
        var inSection = false
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { inSection = true }
            guard !inSection, isTopLevelNotifyLine(trimmed), let entries = parseTomlStringArray(line) else { continue }
            return entries
        }
        return []
    }

    private static func embeddedNotifyContainsMoriHook(_ entry: String) -> Bool {
        guard let payload = entry.data(using: .utf8),
              let nested = try? JSONSerialization.jsonObject(with: payload) as? [String] else { return false }
        return nested.contains { knownCodexHookPaths.contains($0) }
    }

    private static func isTopLevelNotifyLine(_ trimmed: String) -> Bool {
        guard let equals = trimmed.firstIndex(of: "=") else { return false }
        return trimmed[..<equals].trimmingCharacters(in: .whitespaces) == "notify"
    }

    /// Parse a single-line TOML string array without rewriting unsupported TOML values.
    private static func parseTomlStringArray(_ line: String) -> [String]? {
        guard let open = line.firstIndex(of: "["),
              let close = line.lastIndex(of: "]"), open < close else { return nil }
        let array = String(line[open...close])
        guard let data = array.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String]
    }

    /// A JSON array of strings is also valid TOML; reject values we cannot encode safely.
    private static func encodeTomlStringArray(_ values: [String]) -> String? {
        guard let data = try? JSONSerialization.data(
            withJSONObject: values, options: [.withoutEscapingSlashes]
        ) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
