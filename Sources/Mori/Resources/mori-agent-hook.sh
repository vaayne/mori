#!/usr/bin/env bash
# Mori agent hook for Claude Code
# Sets tmux pane options and renames window on agent state transitions.
# Installed automatically by Mori into ~/.claude/settings.json

set -euo pipefail

HOOK_TYPE="${1:-}"
AGENT_NAME="${2:-claude}"

# Read JSON from stdin (required by Claude Code hooks)
cat > /dev/null 2>&1 || true

# Bail if not inside tmux
[ -z "${TMUX:-}" ] && exit 0

# Get the current pane's working directory basename for context
PANE_PATH="$(tmux display-message -p '#{pane_current_path}' 2>/dev/null || echo '')"
DIR_NAME="$(basename "$PANE_PATH" 2>/dev/null || echo '')"

save_original_name() {
    local current
    current="$(tmux display-message -p '#{window_name}' 2>/dev/null || echo '')"
    local saved
    saved="$(tmux show-option -pqv @mori-original-name 2>/dev/null || echo '')"
    if [ -z "$saved" ]; then
        tmux set-option -p @mori-original-name "$current"
    fi
}

set_state() {
    local state="$1"
    local emoji="$2"
    tmux set-option -p @mori-agent-state "$state"
    tmux set-option -p @mori-agent-name "$AGENT_NAME"
    save_original_name
    tmux rename-window "$emoji $AGENT_NAME $DIR_NAME"
}

case "$HOOK_TYPE" in
    UserPromptSubmit|PreToolUse)
        set_state "working" "⚡"
        ;;
    Stop|Notification)
        set_state "done" "✅"
        ;;
    *)
        exit 0
        ;;
esac

exit 0
