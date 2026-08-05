# Agent Hooks

Mori integrates with coding agents (Claude Code, Codex CLI, Pi, and Droid) to display their status in tab names and send notifications. Hooks are manually enabled/disabled in **Settings > Agent Hooks**. Once enabled, Mori refreshes the installed hook files on every launch so `~/.config/mori/` stays aligned with the current app bundle.

## How It Works

When enabled, each agent installs hook scripts that report state changes to tmux via pane options:
- `@mori-agent-state`: `"working"` (agent is running), `"waiting"` (agent finished turn, awaiting input), or `"done"` (agent exited)
- `@mori-agent-name`: Agent name (e.g., `"claude"`, `"codex"`, `"pi"`)

During Mori's 5-second polling cycle, it reads these options directly from tmux — no process scanning, no pattern matching. Tab names show the agent name (e.g., `claude`, `codex`, `pi`), with sidebar badges (⚡ working / ❗ waiting / ✅ done). macOS notifications fire on state transitions.

## Installation

### Claude Code

1. Open Mori Settings > Agent Hooks
2. Toggle **Claude Code** on
3. Mori updates `~/.claude/settings.json` with hooks for:
   - `UserPromptSubmit` (prompt entered)
   - `Stop` (agent stopped)
   - `Notification` (completion notification)
4. On future launches, Mori re-copies the hook script from its bundled resources if the installed file is stale or missing.

Run Claude Code in a tmux window. Tab renames to `claude` while working (⚡ badge shown in sidebar), then shows waiting badge (❗) when the turn completes. Click the waiting badge to reply inline.

### Codex CLI

1. Open Mori Settings > Agent Hooks
2. Toggle **Codex CLI** on
3. Mori creates/updates `~/.codex/hooks.json` with only these lifecycle hooks:
   ```json
   {
     "hooks": {
       "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "/Users/you/.config/mori/hooks/mori-codex-hook.sh UserPromptSubmit" }] }],
       "Stop": [{ "hooks": [{ "type": "command", "command": "/Users/you/.config/mori/hooks/mori-codex-hook.sh Stop" }] }]
     }
   }
   ```

Mori leaves unrelated Codex hooks intact. On refresh, an existing legacy Mori `notify` registration in `~/.codex/config.toml` is migrated to this format and removed without changing other `notify` entries.

On future launches, Mori re-copies the hook script from its bundled resources if the installed file is stale or missing.

Run Codex in a tmux window. Tab renames to `codex` while working (⚡ badge shown in sidebar), then shows waiting badge (❗) when the turn completes.

### Pi

1. Open Mori Settings > Agent Hooks
2. Toggle **Pi** on
3. Mori creates a TypeScript extension at `~/.config/mori/mori-pi-extension.ts` and registers it in `~/.pi/agent/settings.json`:
   ```json
   {
     "extensions": [
       "~/mori-pi-extension.ts"
     ]
   }
   ```
4. On future launches, Mori re-copies the extension from its bundled resources if the installed file is stale or missing.

Run Pi in a tmux window. Tab renames to `pi` while working (⚡ badge shown in sidebar), then shows waiting badge (❗) when the turn completes. Click the waiting badge to reply inline.

## Hook Scripts

Hook scripts are stored in `$XDG_CONFIG_HOME/mori/hooks/` (fallback: `~/.config/mori/hooks/`) and are loaded from Mori's bundle resources. They're shared shell/TypeScript utilities:

### mori-hook-common.sh
Shared bash functions sourced by agent-specific scripts. Sets `@mori-agent-state` and `@mori-agent-name` pane options, then renames the tmux window to the agent name.

### mori-agent-hook.sh (Claude Code)
Responds to Claude Code hook events:
- `UserPromptSubmit` → state: `"working"`
- `Stop`, `Notification` → state: `"waiting"`

Drains stdin (Claude Code pipes JSON hook data) and bails silently if not in tmux.

### mori-codex-hook.sh (Codex CLI)
Handles the two registered Codex events:
- `UserPromptSubmit` → state: `"working"`
- `Stop` → state: `"waiting"`

The script also accepts legacy `notify` JSON (`{"type":"agent-turn-complete",...}`) as a completion event so already-running Codex processes remain compatible during migration. Empty, malformed, and unrecognized arguments do not change state.

### mori-pi-extension.ts (Pi)
TypeScript extension listening to Pi events:
- `agent_start`, `tool_execution_start` → state: `"working"`
- `agent_end` → state: `"waiting"`

## Disabling Hooks

Toggle the agent off in Settings > Agent Hooks. Mori removes:
- Hook script from `~/.config/mori/hooks/`
- Hook entries from agent config files (`~/.claude/settings.json`, `~/.codex/hooks.json`, and legacy Mori entries in `~/.codex/config.toml`, etc.)

If you manually delete hook scripts, toggle off then back on to reinstall.

## Stale Cleanup

When a hook-detected agent exits (tmux pane returns to shell), Mori automatically:
1. Clears `@mori-agent-state` and `@mori-agent-name` pane options
2. Re-enables `automatic-rename` so tmux updates the window name to the current process

This prevents stale agent names from lingering after the agent has stopped.

## Notifications

When an agent completes (state: `"done"`), Mori sends a macOS notification:
- **Title**: `"Claude Code Finished"` (or `"Codex Finished"`, etc.)
- **Body**: Window title and worktree name
- **Sound**: Default system sound

Click the notification to focus the window. Bundled `.app` builds use `UNUserNotificationCenter`; unbundled `swift run` builds fall back to `osascript`.

## Troubleshooting

**Hooks don't seem to fire:**
- Verify the hook script exists: `ls ~/.config/mori/hooks/`
- Check the agent config file was updated correctly:
  - Claude Code: `cat ~/.claude/settings.json | grep mori`
  - Codex: `cat ~/.codex/hooks.json | grep mori`
  - Pi: `cat ~/.pi/agent/settings.json | grep mori`
- Ensure you're running the agent _inside a tmux session_. Hooks only work in tmux.

**Tab name doesn't change to agent name:**
- Reload Mori's tmux polling by switching to another window and back, or restart Mori.
- Check `tmux list-panes -F "#{pane_id} #{@mori-agent-state} #{@mori-agent-name}"` to see if pane options are set.
- Badge should appear in the sidebar even if tab name hasn't updated yet (verify badge shows ⚡ or ✅).

**Hook script permission denied:**
- Reinstall via Settings > Agent Hooks toggle (off then on). Mori sets `0755` permissions on install.

**Codex hooks don't get added:**
- Verify `~/.codex/hooks.json` is readable JSON.
- If you added Mori hooks after Codex created the file, toggle the hook off/on to retry.
- Mori preserves unrecognized or malformed hook files rather than overwriting them; repair invalid JSON first.

## Implementation Details

**AgentHookConfigurator** (Swift):
- Detects installed hooks: `isClaudeHookInstalled()`, `isCodexHookInstalled()`, `isPiExtensionInstalled()`
- Installs/uninstalls: `installClaudeHook()`, `uninstallClaudeHook()`, etc.
- Handles agent config file mutations (JSON for Claude/Codex/Pi; legacy TOML cleanup for Codex)

**WorkspaceManager** (Swift):
- Reads `@mori-agent-state` and `@mori-agent-name` during 5s tmux poll
- Maps hook states (`"working"` → `.running`, `"done"` → `.completed`)
- Updates `RuntimeWindow.detectedAgent` and window badges
- Clears stale pane options when agent exits

**TmuxBackend** (Swift):
- New methods: `unsetPaneOption()`, `setWindowOption()`
- TmuxParser includes agent fields in pane format string

**TmuxCommandRunner** (Swift):
- Improved environment loading: checks inherited PATH first (instant), falls back to login shell with 10s timeout
- Prevents hanging on `.app` bundle launch with minimal environment

## Files Modified

- `Sources/Mori/App/AgentHookConfigurator.swift` — Hook install/uninstall logic
- `Sources/Mori/App/WorkspaceManager.swift` — Hook state reading and cleanup
- `Sources/Mori/App/NotificationManager.swift` — Agent name in notifications
- `Sources/Mori/Resources/mori-*.sh` — Hook scripts
- `Sources/Mori/Resources/mori-pi-extension.ts` — Pi extension
- `Packages/MoriCore/Models/RuntimeWindow.swift` — Added `detectedAgent` field
- `Packages/MoriTmux/Sources/MoriTmux/TmuxBackend.swift` — Pane option getters/setters
- `Packages/MoriUI/Sources/MoriUI/GhosttySettingsView.swift` — Agent Hooks settings tab

## See Also

- [Keymaps](keymaps.md)
- CLAUDE.md — Agent-Aware Tabs section
