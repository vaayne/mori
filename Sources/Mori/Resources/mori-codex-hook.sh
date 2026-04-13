#!/usr/bin/env bash
# Mori agent hook for Codex CLI
# Sets tmux pane options and renames window on agent state transitions.

set -euo pipefail

AGENT_NAME="codex"

# Bail if not inside tmux
[ -z "${TMUX:-}" ] && exit 0

# Determine hook type.
# Legacy notify: JSON payload as first arg with "type" field, e.g. {"type":"agent-turn-complete",...}
# Modern codex_hooks: first arg is the event name (UserPromptSubmit, Stop, etc.)
# No args: treat as done.
RAW_ARG="${1:-}"

if [ -z "$RAW_ARG" ]; then
    HOOK_TYPE="Stop"
elif echo "$RAW_ARG" | grep -q '^{'; then
    # JSON arg — extract "type" field
    HOOK_TYPE="$(echo "$RAW_ARG" | sed -n 's/.*"type" *: *"\([^"]*\)".*/\1/p')"
    [ -z "$HOOK_TYPE" ] && HOOK_TYPE="Stop"
else
    HOOK_TYPE="$RAW_ARG"
fi

# Drain stdin if present (modern hooks send JSON on stdin)
cat > /dev/null 2>&1 || true

# shellcheck source=mori-hook-common.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/mori-hook-common.sh"

case "$HOOK_TYPE" in
    UserPromptSubmit)
        set_state "working"
        ;;
    Stop|Notification|agent-turn-complete)
        set_state "waiting"
        ;;
    *)
        exit 0
        ;;
esac

exit 0
