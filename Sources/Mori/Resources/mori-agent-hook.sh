#!/usr/bin/env bash
# Mori agent hook for Claude Code
# Sets tmux pane options and renames window on agent state transitions.

set -euo pipefail

HOOK_TYPE="${1:-}"
AGENT_NAME="${2:-claude}"

# Read JSON from stdin (required by Claude Code hooks)
cat > /dev/null 2>&1 || true

# Bail if not inside tmux
[ -z "${TMUX:-}" ] && exit 0

# shellcheck source=mori-hook-common.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/mori-hook-common.sh"

case "$HOOK_TYPE" in
    UserPromptSubmit|PreToolUse)
        set_state "working"
        ;;
    Stop|Notification)
        set_state "done"
        ;;
    *)
        exit 0
        ;;
esac

exit 0
