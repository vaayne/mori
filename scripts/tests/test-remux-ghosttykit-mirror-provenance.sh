#!/usr/bin/env bash
# Prove a release cannot reuse a byte-valid upstream-development cache.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fetch="$repo_root/scripts/fetch-remux-ghosttykit.sh"
source_framework="$repo_root/Frameworks/RemuxGhosttyKit.xcframework"
source_provenance="$repo_root/Frameworks/.remux-ghosttykit-provenance"
[[ -d "$source_framework" && -f "$source_provenance" ]] || {
    echo "Install the pinned framework first: bash scripts/fetch-remux-ghosttykit.sh --force" >&2
    exit 1
}

tmp="$(mktemp -d "${TMPDIR:-/tmp}/mori-remux-mirror-provenance.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
frameworks="$tmp/Frameworks"
mkdir -p "$frameworks" "$tmp/bin"
cp -R "$source_framework" "$frameworks/RemuxGhosttyKit.xcframework"
cat >"$frameworks/.remux-ghosttykit-provenance" <<'PROVENANCE'
release_tag=ghosttykit-20260731
archive_sha256=e54ca81edf40721f72e87b5a5449746cd8fdcc877d5b0f284cdf2e34609f21f9
framework_tree_sha256=ccf9e7ae738734c4d41bfb9abd82d51277c440bdc3a8a764728b6afb893b28a5
source_kind=upstream-development-only
archive_url=https://github.com/h3nock/remux-ghostty/releases/download/ghosttykit-20260731/GhosttyKit.xcframework.zip
source_repository=https://github.com/h3nock/remux-ghostty
source_commit=aeb8f73790946d9c9ad175b3dafaec9911ef36bb
PROVENANCE

# A normal local/PR fetch remains idempotent and does not request a download.
cat >"$tmp/bin/curl" <<'CURL'
#!/usr/bin/env bash
printf 'called\n' >> "$REMUX_TEST_CURL_CALLS"
exit 22
CURL
chmod +x "$tmp/bin/curl"
: >"$tmp/curl-calls"
PATH="$tmp/bin:$PATH" REMUX_TEST_CURL_CALLS="$tmp/curl-calls" REMUX_GHOSTTYKIT_FRAMEWORKS_DIR="$frameworks" "$fetch"
[[ ! -s "$tmp/curl-calls" ]] || { echo "Normal fetch unexpectedly downloaded a valid cache." >&2; exit 1; }

# A required mirror must discard that same verified upstream cache and attempt
# the mirror. The fake downloader fails after recording only that it was called.
secret_mirror_url="https://mirror.example.invalid/private/signed-artifact?token=not-for-provenance"
if PATH="$tmp/bin:$PATH" REMUX_TEST_CURL_CALLS="$tmp/curl-calls" REMUX_GHOSTTYKIT_FRAMEWORKS_DIR="$frameworks" MORI_REMUX_GHOSTTYKIT_MIRROR_URL="$secret_mirror_url" "$fetch" --require-mirror >"$tmp/fetch.out" 2>"$tmp/fetch.err"; then
    echo "Required mirror accepted an upstream-provenance cache." >&2
    exit 1
fi
[[ -s "$tmp/curl-calls" ]] || { echo "Required mirror did not attempt a refetch." >&2; exit 1; }
[[ ! -e "$frameworks/RemuxGhosttyKit.xcframework" && ! -e "$frameworks/.remux-ghosttykit-provenance" ]] || {
    echo "Required mirror retained the upstream-provenance cache." >&2
    exit 1
}
! grep -R -F "$secret_mirror_url" "$tmp" || { echo "Mirror URL leaked to persisted test output." >&2; exit 1; }
# The writer contains the upstream URL only in its development branch; release
# provenance has only the canonical source_kind/source_marker fields.
! grep -F 'archive_url=$release_url' "$fetch" || { echo "Mirror URL is persisted in provenance." >&2; exit 1; }
grep -F "printf 'archive_url=%s\\n' \"\$UPSTREAM_RELEASE_URL\"" "$fetch" >/dev/null || {
    echo "Development provenance no longer records the canonical upstream URL." >&2
    exit 1
}

echo "✅ Required mirror discards upstream cache, refetches, and keeps mirror URL out of provenance"
