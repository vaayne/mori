import Foundation

/// Installs Mori agent hook scripts and configures coding agents to use them.
/// Writes hook scripts to ~/Library/Application Support/Mori/hooks/
/// and merges hook entries into agent config files.
enum AgentHookConfigurator {

    /// Display names for notifications, keyed by agent process name.
    static let agentDisplayNames: [String: String] = [
        "claude": "Claude Code",
        "codex": "Codex",
        "pi": "Pi",
    ]

    private static let home = FileManager.default.homeDirectoryForCurrentUser

    private static var hooksDir: URL {
        // Use ~/.config/mori/hooks/ — no spaces in path, avoids shell word-splitting
        home.appendingPathComponent(".config/mori/hooks")
    }

    // MARK: - Public

    /// Install all agent hooks. Safe to call repeatedly.
    static func installAllHooks() {
        ensureHooksDir()
        installClaudeHook()
        installCodexHook()
        installPiExtension()
    }

    /// Install Claude Code hook only.
    static func installClaudeHook() {
        ensureHooksDir()
        guard let path = installScript(name: "mori-agent-hook", source: claudeHookScript) else { return }
        configureClaudeSettings(hookPath: path)
    }

    // MARK: - Directory Setup

    private static func ensureHooksDir() {
        try? FileManager.default.createDirectory(at: hooksDir, withIntermediateDirectories: true)
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

        for event in ["UserPromptSubmit", "PreToolUse", "Stop", "Notification"] {
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

    private static func installCodexHook() {
        guard let path = installScript(name: "mori-codex-hook", source: codexHookScript) else { return }
        configureCodexSettings(hookPath: path)
    }

    private static func configureCodexSettings(hookPath: String) {
        let configURL = home.appendingPathComponent(".codex/config.toml")

        // Read existing config
        let existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""

        // Check if Mori hook is already configured
        if existing.contains(hookPath) { return }

        // Ensure directory exists
        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        // Append legacy notify hook (fires on agent-turn-complete)
        var config = existing
        if !config.hasSuffix("\n") && !config.isEmpty { config += "\n" }
        config += "\n# Mori agent status hook\n"
        config += "notify = [\"\(hookPath)\"]\n"
        try? config.write(to: configURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Pi

    private static func installPiExtension() {
        let extensionURL = home
            .appendingPathComponent(".pi/agent/extensions/mori-tmux.ts")
        installFile(at: extensionURL, content: piExtensionSource)
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

    private static func writeJSON(_ object: [String: Any], to url: URL) {
        guard let data = try? JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Hook Script Sources

    private static let claudeHookScript = """
    #!/usr/bin/env bash
    set -euo pipefail
    HOOK_TYPE="${1:-}"; AGENT_NAME="${2:-claude}"
    cat > /dev/null 2>&1 || true
    [ -z "${TMUX:-}" ] && exit 0
    PANE_PATH="$(tmux display-message -p '#{pane_current_path}' 2>/dev/null || echo '')"
    DIR_NAME="$(basename "$PANE_PATH" 2>/dev/null || echo '')"
    save_original_name() {
        local saved; saved="$(tmux show-option -pqv @mori-original-name 2>/dev/null || echo '')"
        if [ -z "$saved" ]; then tmux set-option -p @mori-original-name "$(tmux display-message -p '#{window_name}' 2>/dev/null)"; fi
    }
    set_state() {
        tmux set-option -p @mori-agent-state "$1"
        tmux set-option -p @mori-agent-name "$AGENT_NAME"
        save_original_name
        tmux rename-window "$2 $AGENT_NAME $DIR_NAME"
    }
    case "$HOOK_TYPE" in
        UserPromptSubmit|PreToolUse) set_state "working" "⚡" ;;
        Stop|Notification) set_state "done" "✅" ;;
    esac
    exit 0
    """

    private static let codexHookScript = """
    #!/usr/bin/env bash
    set -euo pipefail
    AGENT_NAME="codex"; HOOK_TYPE="${1:-}"
    [ -z "$HOOK_TYPE" ] && HOOK_TYPE="Stop"
    cat > /dev/null 2>&1 || true
    [ -z "${TMUX:-}" ] && exit 0
    PANE_PATH="$(tmux display-message -p '#{pane_current_path}' 2>/dev/null || echo '')"
    DIR_NAME="$(basename "$PANE_PATH" 2>/dev/null || echo '')"
    save_original_name() {
        local saved; saved="$(tmux show-option -pqv @mori-original-name 2>/dev/null || echo '')"
        if [ -z "$saved" ]; then tmux set-option -p @mori-original-name "$(tmux display-message -p '#{window_name}' 2>/dev/null)"; fi
    }
    set_state() {
        tmux set-option -p @mori-agent-state "$1"
        tmux set-option -p @mori-agent-name "$AGENT_NAME"
        save_original_name
        tmux rename-window "$2 $AGENT_NAME $DIR_NAME"
    }
    case "$HOOK_TYPE" in
        UserPromptSubmit|PreToolUse) set_state "working" "⚡" ;;
        Stop|Notification|agent-turn-complete) set_state "done" "✅" ;;
    esac
    exit 0
    """

    private static let piExtensionSource = """
    // Mori integration for Pi coding agent
    // Auto-installed by Mori to ~/.pi/agent/extensions/mori-tmux.ts

    export default function (pi: any) {
      const AGENT_NAME = "pi";
      async function tmux(...args: string[]) {
        try { await pi.exec("tmux", args); } catch {}
      }
      async function saveOriginalName() {
        try {
          const r = await pi.exec("tmux", ["show-option", "-pqv", "@mori-original-name"]);
          if (!r?.stdout?.trim()) {
            const n = await pi.exec("tmux", ["display-message", "-p", "#{window_name}"]);
            await tmux("set-option", "-p", "@mori-original-name", n?.stdout?.trim() || "");
          }
        } catch {}
      }
      async function getDirName(): Promise<string> {
        try {
          const r = await pi.exec("tmux", ["display-message", "-p", "#{pane_current_path}"]);
          return (r?.stdout?.trim() || "").split("/").pop() || "";
        } catch { return ""; }
      }
      async function setState(state: string, emoji: string) {
        const d = await getDirName();
        await tmux("set-option", "-p", "@mori-agent-state", state);
        await tmux("set-option", "-p", "@mori-agent-name", AGENT_NAME);
        await saveOriginalName();
        await tmux("rename-window", `${emoji} ${AGENT_NAME} ${d}`);
      }
      pi.on("agent_start", async () => { await setState("working", "⚡"); });
      pi.on("agent_end", async () => { await setState("done", "✅"); });
      pi.on("tool_execution_start", async () => { await setState("working", "⚡"); });
    }
    """
}
