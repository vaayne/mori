#!/usr/bin/env bash
# Mori agent hook for Codex CLI
# Sets tmux pane options and renames window on agent state transitions.

set -euo pipefail

AGENT_NAME="codex"

# Bail if not inside tmux
[ -z "${TMUX:-}" ] && exit 0

# Determine hook type. Modern hooks pass an explicit event argument. Legacy `notify`
# passed a JSON payload as arg 1, so retain its completion mapping for Codex processes
# that were already running when Mori migrated their registration.
RAW_ARG="${1:-}"

case "$RAW_ARG" in
    UserPromptSubmit|Stop)
        HOOK_TYPE="$RAW_ARG"
        ;;
    \{*)
        HOOK_TYPE="$(printf '%s' "$RAW_ARG" | sed -n 's/.*"type"[[:space:]]*:[[:space:]]*"\([^\"]*\)".*/\1/p')"
        ;;
    *)
        # Empty, malformed, and unknown events must not manufacture a waiting state.
        exit 0
        ;;
esac

# Modern Codex hooks send their payload on stdin. Consume it even though the
# explicit event argument is sufficient, so the producer never blocks on a full pipe.
cat > /dev/null 2>&1 || true

# shellcheck source=mori-hook-common.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/mori-hook-common.sh"

case "$HOOK_TYPE" in
    UserPromptSubmit)
        set_state "working"
        ;;
    Stop|agent-turn-complete)
        set_state "waiting"
        ;;
    *)
        exit 0
        ;;
esac

exit 0
