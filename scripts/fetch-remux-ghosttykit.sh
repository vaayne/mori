#!/usr/bin/env bash
# Install the pinned iOS GhosttyKit used solely by MoriRemote's remux runtime.
# The XCFramework is intentionally ignored: do not commit this release asset.
set -euo pipefail

readonly RELEASE_TAG="ghosttykit-20260731"
readonly ARCHIVE_SHA256="e54ca81edf40721f72e87b5a5449746cd8fdcc877d5b0f284cdf2e34609f21f9"
readonly FRAMEWORK_TREE_SHA256="ccf9e7ae738734c4d41bfb9abd82d51277c440bdc3a8a764728b6afb893b28a5"
readonly UPSTREAM_RELEASE_URL="https://github.com/h3nock/remux-ghostty/releases/download/${RELEASE_TAG}/GhosttyKit.xcframework.zip"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
frameworks_dir="${REMUX_GHOSTTYKIT_FRAMEWORKS_DIR:-$repo_root/Frameworks}"
framework_path="$frameworks_dir/RemuxGhosttyKit.xcframework"
provenance_path="$frameworks_dir/.remux-ghosttykit-provenance"

verify_installed_framework() {
    REMUX_GHOSTTYKIT_XCFRAMEWORK="$framework_path" "$repo_root/scripts/verify-remux-ghosttykit.sh"
}

provenance_value() {
    local key="$1"
    [[ -f "$provenance_path" ]] || return 0
    awk -F= -v key="$key" '$1 == key { print substr($0, length(key) + 2); exit }' "$provenance_path"
}

force=0
require_mirror=0
while (($#)); do
    case "$1" in
        --force) force=1 ;;
        --require-mirror) require_mirror=1 ;;
        *)
            echo "Usage: $0 [--force] [--require-mirror]" >&2
            exit 2
            ;;
    esac
    shift
done

# A release build must name a Mori-controlled location explicitly. The pinned
# bytes, source commit, and tree digest remain script constants: callers cannot
# turn this into a floating or differently checksummed dependency.
mirror_url="${MORI_REMUX_GHOSTTYKIT_MIRROR_URL:-}"
if ((require_mirror)) && [[ -z "$mirror_url" ]]; then
    cat >&2 <<'EOF'
Mori-controlled RemuxGhosttyKit mirror is not configured.
Set MORI_REMUX_GHOSTTYKIT_MIRROR_URL to the byte-identical Mori-controlled asset,
then rerun. The asset must match this script's pinned SHA-256 exactly; do not
substitute a third-party maintainer URL for a release build.
EOF
    exit 1
fi
release_url="${mirror_url:-$UPSTREAM_RELEASE_URL}"
source_kind="${mirror_url:+mori-controlled-mirror}"
source_kind="${source_kind:-upstream-development-only}"

if [[ -d "$framework_path" && "$force" -eq 0 ]]; then
    if verify_installed_framework; then
        if ((require_mirror)) && [[ "$(provenance_value source_kind)" != "mori-controlled-mirror" ]]; then
            # A PR cache may contain byte-valid upstream development output.
            # TestFlight must consume the configured Mori mirror instead.
            echo "Discarding non-mirror RemuxGhosttyKit cache before required mirror fetch." >&2
            rm -rf "$framework_path" "$provenance_path"
        else
            echo "Pinned RemuxGhosttyKit is already installed at $framework_path"
            exit 0
        fi
    elif ((require_mirror)); then
        # A release must not retain an invalid cache while retrying its mirror.
        echo "Discarding unverifiable RemuxGhosttyKit cache before required mirror fetch." >&2
        rm -rf "$framework_path" "$provenance_path"
    else
        echo "Existing framework failed verification; refusing to replace it without --force." >&2
        exit 1
    fi
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/mori-remux-ghosttykit.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
archive="$work_dir/GhosttyKit.xcframework.zip"
extract_dir="$work_dir/extracted"

printf 'Downloading Remux GhosttyKit %s from %s...\n' "$RELEASE_TAG" "$source_kind"
curl --fail --location --retry 3 --output "$archive" "$release_url"
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

framework_tree_sha256() {
    local root="$1"
    find "$root" -type f -print0 | LC_ALL=C sort -z | while IFS= read -r -d '' file; do
        printf '%s  %s\n' "$(shasum -a 256 "$file" | awk '{print $1}')" "${file#"$root"/}"
    done | shasum -a 256 | awk '{print $1}'
}
actual_tree_sha256="$(framework_tree_sha256 "$staged_framework")"
if [[ "$actual_tree_sha256" != "$FRAMEWORK_TREE_SHA256" ]]; then
    printf 'Framework content digest mismatch:\n  expected: %s\n  actual:   %s\n' "$FRAMEWORK_TREE_SHA256" "$actual_tree_sha256" >&2
    exit 1
fi

mkdir -p "$frameworks_dir"
staged_install="$frameworks_dir/.RemuxGhosttyKit.xcframework.staging.$$"
rm -rf "$staged_install"
cp -R "$staged_framework" "$staged_install"
rm -rf "$framework_path"
mv "$staged_install" "$framework_path"
{
    printf 'release_tag=%s\n' "$RELEASE_TAG"
    printf 'archive_sha256=%s\n' "$ARCHIVE_SHA256"
    printf 'framework_tree_sha256=%s\n' "$FRAMEWORK_TREE_SHA256"
    printf 'source_kind=%s\n' "$source_kind"
    if [[ "$source_kind" == "mori-controlled-mirror" ]]; then
        # The canonical marker proves release-cache provenance without storing
        # a potentially signed or private mirror URL in a persistent cache.
        printf 'source_marker=mori-controlled-mirror\n'
    else
        printf 'archive_url=%s\n' "$UPSTREAM_RELEASE_URL"
    fi
    printf 'source_repository=https://github.com/h3nock/remux-ghostty\n'
    printf 'source_commit=aeb8f73790946d9c9ad175b3dafaec9911ef36bb\n'
} >"$provenance_path"

verify_installed_framework
printf 'Installed and verified %s at %s\n' "$RELEASE_TAG" "$framework_path"
