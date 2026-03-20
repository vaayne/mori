#!/usr/bin/env bash
# Mori agent hook for Codex CLI
# Supports both legacy notify (JSON as last arg) and modern codex_hooks (JSON on stdin).
# Sets tmux pane options and renames window on agent state transitions.

set -euo pipefail

AGENT_NAME="codex"

# Bail if not inside tmux
[ -z "${TMUX:-}" ] && exit 0

# Determine hook type.
# Modern codex_hooks: first arg is the event name (UserPromptSubmit, Stop, etc.)
# Legacy notify: no args, JSON payload as last arg with "type" field.
HOOK_TYPE="${1:-}"

if [ -z "$HOOK_TYPE" ]; then
    # Legacy notify: always means agent-turn-complete = done
    HOOK_TYPE="Stop"
fi

# Drain stdin if present (modern hooks send JSON on stdin)
cat > /dev/null 2>&1 || true

PANE_PATH="$(tmux display-message -p '#{pane_current_path}' 2>/dev/null || echo '')"
DIR_NAME="$(basename "$PANE_PATH" 2>/dev/null || echo '')"

save_original_name() {
    local saved
    saved="$(tmux show-option -pqv @mori-original-name 2>/dev/null || echo '')"
    if [ -z "$saved" ]; then
        tmux set-option -p @mori-original-name "$(tmux display-message -p '#{window_name}' 2>/dev/null)"
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
    Stop|Notification|agent-turn-complete)
        set_state "done" "✅"
        ;;
    *)
        exit 0
        ;;
esac

exit 0
