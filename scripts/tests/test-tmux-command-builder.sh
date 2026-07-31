#!/usr/bin/env bash
# Host-only contract test. Compile the exact production Foundation-only command
# assembler, then execute its generated shell against a fake absolute executable.
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/../.." && pwd)
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
fake="$root/fake tmux"
output="$root/argv"
fixture="$root/main.swift"
runner="$root/tmux-command-fixture"

cat >"$fake" <<'EOF'
#!/usr/bin/env bash
: "${ARGV_OUTPUT:?}"
printf '%s\0' "$@" > "$ARGV_OUTPUT"
EOF
chmod +x "$fake"

cat >"$fixture" <<'EOF'
import Foundation
let arguments = ["two words", "", "it's quoted; touch should-not-run", "-leading-dash"]
print(TmuxShellCommand.command(executable: CommandLine.arguments[1], arguments: arguments))
EOF
xcrun swiftc "$repo_root/MoriRemote/MoriRemote/Tmux/TmuxShellCommand.swift" "$fixture" -o "$runner"
generated=$("$runner" "$fake")
ARGV_OUTPUT="$output" /bin/sh -c "$generated"
python3 - "$output" <<'PY'
import pathlib, sys
actual = pathlib.Path(sys.argv[1]).read_bytes().split(b'\0')[:-1]
expected = [b'two words', b'', b"it's quoted; touch should-not-run", b'-leading-dash']
if actual != expected:
    raise SystemExit(f'argv mismatch: {actual!r} != {expected!r}')
PY
if [[ -e "$root/should-not-run" ]]; then
  echo 'quoted semicolon executed unexpectedly' >&2
  exit 1
fi
printf 'tmux command builder argv contract passed\n'
