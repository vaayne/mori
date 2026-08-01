#!/usr/bin/env bash
# Exercise the verifier against a disposable copy; never alter the ignored real framework.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_framework="$repo_root/Frameworks/GhosttyKit.xcframework"
source_provenance="$repo_root/Frameworks/.ghosttykit-provenance"
[[ -d "$source_framework" && -f "$source_provenance" ]] || {
    echo "Build the universal framework first: mise run build:ghostty-universal" >&2
    exit 1
}

tmp="$(mktemp -d "${TMPDIR:-/tmp}/mori-ghosttykit-verify.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
cp -R "$source_framework" "$tmp/GhosttyKit.xcframework"
cp "$source_provenance" "$tmp/.ghosttykit-provenance"

MORI_GHOSTTYKIT_XCFRAMEWORK="$tmp/GhosttyKit.xcframework" "$repo_root/scripts/verify-ghosttykit.sh"
printf '\nmutation\n' >> "$tmp/GhosttyKit.xcframework/Info.plist"
if MORI_GHOSTTYKIT_XCFRAMEWORK="$tmp/GhosttyKit.xcframework" "$repo_root/scripts/verify-ghosttykit.sh"; then
    echo "Verifier accepted a modified framework." >&2
    exit 1
fi

echo "✅ GhosttyKit verifier rejects a modified framework"
