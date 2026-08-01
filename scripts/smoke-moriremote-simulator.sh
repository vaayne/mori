#!/usr/bin/env bash
# Install and prove both the library and deterministic terminal-facade paths stay alive.
# simctl launch returning a PID is intentionally not accepted as success.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
configuration="${MORI_IOS_CONFIGURATION:-Debug}"
derived_data="${DERIVED_DATA:-$repo_root/.derived-data}"
bundle_id="com.vaayne.mori-remote"
output_dir="${MORI_IOS_SMOKE_OUTPUT:-$derived_data/moriremote-smoke}"
device="${MORI_IOS_SIMULATOR:-}"

if [[ -z "$device" ]]; then
    device="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ { print $2; exit }')"
fi
[[ -n "$device" ]] || { echo "No available iPhone simulator." >&2; exit 1; }

app_path="$(find "$derived_data" -type d -path "*/${configuration}-iphonesimulator/MoriRemote.app" -print -quit)"
[[ -n "$app_path" ]] || { echo "MoriRemote.app (${configuration}) not found below $derived_data. Build it first." >&2; exit 1; }

mkdir -p "$output_dir"
xcrun simctl boot "$device" 2>/dev/null || true
xcrun simctl bootstatus "$device" -b
xcrun simctl install "$device" "$app_path"

assert_alive() {
    local pid="$1" label="$2"
    # Let a launch-time abort win before testing the process table.
    sleep 3
    local processes
    processes="$(xcrun simctl spawn "$device" /bin/ps -axo pid=,comm=)"
    if ! awk -v pid="$pid" '$1 == pid && $0 ~ /MoriRemote\.app\/MoriRemote$/ { found = 1 } END { exit !found }' <<<"$processes"; then
        echo "MoriRemote $label launch PID $pid is not alive." >&2
        printf '%s\n' "$processes" >&2
        return 1
    fi
    # A live PID can still be an app headed for a fatal abort. Fail on the
    # simulator's process-attributed crash/termination diagnostics too.
    local logs log_error
    log_error="$(mktemp "${TMPDIR:-/tmp}/mori-simctl-log.XXXXXX")"
    if ! logs="$(xcrun simctl spawn "$device" log show --style compact --last 20s --predicate 'process == "MoriRemote" AND (eventMessage CONTAINS[c] "Terminating app" OR eventMessage CONTAINS[c] "fatal error" OR eventMessage CONTAINS[c] "uncaught exception")' 2>"$log_error" | awk 'NR > 1')"; then
        echo "Unable to inspect MoriRemote simulator crash diagnostics:" >&2
        cat "$log_error" >&2
        rm -f "$log_error"
        return 1
    fi
    rm -f "$log_error"
    if [[ -n "$logs" ]]; then
        echo "MoriRemote $label emitted fatal simulator diagnostics:" >&2
        printf '%s\n' "$logs" >&2
        return 1
    fi
}

probe_logs() {
    local pid="$1"
    xcrun simctl spawn "$device" log show --style compact --last 1m \
        --predicate "process == \"MoriRemote\" AND processID == $pid AND eventMessage CONTAINS \"MORI_GHOSTTY_PROBE_RESULT\"" \
        2>/dev/null | awk 'NR > 1'
}

wait_for_probe_result() {
    local pid="$1"
    local deadline=$((SECONDS + 30)) logs
    while ((SECONDS < deadline)); do
        logs="$(probe_logs "$pid")"
        if grep -Fq 'MORI_GHOSTTY_PROBE_RESULT success=false' <<<"$logs"; then
            echo "Ghostty terminal-facade probe reported startup failure:" >&2
            printf '%s\n' "$logs" >&2
            return 1
        fi
        if grep -Fq 'MORI_GHOSTTY_PROBE_RESULT success=true' <<<"$logs"; then
            return 0
        fi
        sleep 1
    done
    echo "Ghostty terminal-facade probe did not report successful startup within 30 seconds:" >&2
    probe_logs "$pid" >&2 || true
    return 1
}

launch_and_capture() {
    local label="$1"
    shift
    local launch_result pid
    launch_result="$(xcrun simctl launch --terminate-running-process "$device" "$bundle_id" "$@")"
    # Current simctl prints either a PID or "bundle.identifier: PID".
    pid="${launch_result##*: }"
    [[ "$pid" =~ ^[0-9]+$ ]] || { echo "Unexpected simctl launch result: $launch_result" >&2; return 1; }
    assert_alive "$pid" "$label"
    if [[ "$label" == "ghostty-terminal" ]]; then
        wait_for_probe_result "$pid"
    fi
    xcrun simctl io "$device" screenshot "$output_dir/${label}.png"
    [[ -s "$output_dir/${label}.png" ]] || { echo "Missing $label screenshot." >&2; return 1; }
}

launch_and_capture library
launch_and_capture ghostty-terminal --ghostty-terminal-probe

echo "✅ MoriRemote simulator smoke passed on $device"
echo "   Screenshots: $output_dir/library.png, $output_dir/ghostty-terminal.png"
