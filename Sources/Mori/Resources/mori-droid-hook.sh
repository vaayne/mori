#!/usr/bin/env bash
# Mori agent hook for Factory Droid
# Sets tmux pane options and renames window on agent state transitions.

set -euo pipefail

HOOK_TYPE="${1:-}"
AGENT_NAME="droid"

# Read JSON from stdin (required by Droid hooks)
cat > /dev/null 2>&1 || true

# Bail if not inside tmux
[ -z "${TMUX:-}" ] && exit 0

# shellcheck source=mori-hook-common.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/mori-hook-common.sh"

case "$HOOK_TYPE" in
    UserPromptSubmit)
        set_state "working"
        ;;
    Stop|Notification)
        set_state "waiting"
        ;;
    *)
        exit 0
        ;;
esac

exit 0
