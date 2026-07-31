#!/usr/bin/env bash
# Exercise the verifier against a disposable copy; never alter the ignored real framework.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_framework="$repo_root/Frameworks/RemuxGhosttyKit.xcframework"
source_provenance="$repo_root/Frameworks/.remux-ghosttykit-provenance"
[[ -d "$source_framework" && -f "$source_provenance" ]] || {
    echo "Install the pinned framework first: bash scripts/fetch-remux-ghosttykit.sh --force" >&2
    exit 1
}

tmp="$(mktemp -d "${TMPDIR:-/tmp}/mori-remux-verify.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
cp -R "$source_framework" "$tmp/RemuxGhosttyKit.xcframework"
cp "$source_provenance" "$tmp/.remux-ghosttykit-provenance"

REMUX_GHOSTTYKIT_XCFRAMEWORK="$tmp/RemuxGhosttyKit.xcframework" "$repo_root/scripts/verify-remux-ghosttykit.sh"
# Alter a non-ABI metadata file to prove the pinned full-tree digest, not only
# the static library symbols, guards cache contents.
printf '\nmutation\n' >> "$tmp/RemuxGhosttyKit.xcframework/Info.plist"
if REMUX_GHOSTTYKIT_XCFRAMEWORK="$tmp/RemuxGhosttyKit.xcframework" "$repo_root/scripts/verify-remux-ghosttykit.sh"; then
    echo "Verifier accepted a mutated framework." >&2
    exit 1
fi

echo "✅ RemuxGhosttyKit verifier rejects a modified cached artifact"
