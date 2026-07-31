#!/usr/bin/env bash
# Install the pinned iOS GhosttyKit used solely by the MoriRemote remux probe.
# The XCFramework is intentionally ignored: do not commit this release asset.
set -euo pipefail

readonly RELEASE_TAG="ghosttykit-20260731"
readonly ARCHIVE_SHA256="e54ca81edf40721f72e87b5a5449746cd8fdcc877d5b0f284cdf2e34609f21f9"
readonly RELEASE_URL="https://github.com/h3nock/remux-ghostty/releases/download/${RELEASE_TAG}/GhosttyKit.xcframework.zip"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
frameworks_dir="$repo_root/Frameworks"
framework_path="$frameworks_dir/RemuxGhosttyKit.xcframework"
provenance_path="$frameworks_dir/.remux-ghosttykit-provenance"

force=0
case "${1:-}" in
    "") ;;
    --force) force=1 ;;
    *)
        echo "Usage: $0 [--force]" >&2
        exit 2
        ;;
esac

if [[ -d "$framework_path" && "$force" -eq 0 ]]; then
    if "$repo_root/scripts/verify-remux-ghosttykit.sh"; then
        echo "Pinned RemuxGhosttyKit is already installed at $framework_path"
        exit 0
    fi
    echo "Existing framework failed verification; refusing to replace it without --force." >&2
    exit 1
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/mori-remux-ghosttykit.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
archive="$work_dir/GhosttyKit.xcframework.zip"
extract_dir="$work_dir/extracted"

printf 'Downloading Remux GhosttyKit %s...\n' "$RELEASE_TAG"
curl --fail --location --retry 3 --output "$archive" "$RELEASE_URL"
actual_sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
if [[ "$actual_sha256" != "$ARCHIVE_SHA256" ]]; then
    printf 'Checksum mismatch:\n  expected: %s\n  actual:   %s\n' "$ARCHIVE_SHA256" "$actual_sha256" >&2
    exit 1
fi

ditto -x -k "$archive" "$extract_dir"
staged_framework="$extract_dir/RemuxGhosttyKit.xcframework"
if [[ ! -d "$staged_framework" ]]; then
    # The upstream archive is named GhosttyKit; rename only the local installation.
    staged_framework="$extract_dir/GhosttyKit.xcframework"
fi
if [[ ! -d "$staged_framework" ]]; then
    echo "Archive does not contain GhosttyKit.xcframework at its root." >&2
    exit 1
fi

mkdir -p "$frameworks_dir"
staged_install="$frameworks_dir/.RemuxGhosttyKit.xcframework.staging.$$"
rm -rf "$staged_install"
cp -R "$staged_framework" "$staged_install"
rm -rf "$framework_path"
mv "$staged_install" "$framework_path"
cat >"$provenance_path" <<EOF
release_tag=$RELEASE_TAG
archive_sha256=$ARCHIVE_SHA256
archive_url=$RELEASE_URL
source_repository=https://github.com/h3nock/remux-ghostty
source_commit=aeb8f73790946d9c9ad175b3dafaec9911ef36bb
EOF

"$repo_root/scripts/verify-remux-ghosttykit.sh"
printf 'Installed and verified %s at %s\n' "$RELEASE_TAG" "$framework_path"
