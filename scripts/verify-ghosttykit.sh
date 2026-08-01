#!/usr/bin/env bash
# Verify the locked universal GhosttyKit layout, provenance, and remux tmux C ABI.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=ghosttykit-contract.sh
source "$repo_root/scripts/ghosttykit-contract.sh"
ghosttykit_load_contract "$repo_root/ghosttykit-lock.json"

xcframework="${MORI_GHOSTTYKIT_XCFRAMEWORK:-$repo_root/Frameworks/GhosttyKit.xcframework}"
framework_dir="$(dirname "$xcframework")"
provenance_path="${MORI_GHOSTTYKIT_PROVENANCE:-$framework_dir/.ghosttykit-provenance}"
if [[ -z "${MORI_GHOSTTYKIT_PROVENANCE:-}" && ! -f "$provenance_path" && -f "$framework_dir/ghosttykit-provenance.json" ]]; then
    provenance_path="$framework_dir/ghosttykit-provenance.json"
fi

fail() {
    echo "GhosttyKit verification failed: $*" >&2
    exit 1
}

[[ -f "$xcframework/Info.plist" ]] || fail "missing Info.plist at $xcframework"
[[ -f "$provenance_path" ]] || fail "missing provenance record at $provenance_path"

read_provenance() {
    local key="$1"
    if [[ "$provenance_path" == *.json ]]; then
        python3 - "$provenance_path" "$key" <<'PY'
import json
import sys

class DuplicateKey(ValueError):
    pass

def no_duplicates(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise DuplicateKey(key)
        value[key] = item
    return value

path, key = sys.argv[1:]
with open(path, encoding="utf-8") as stream:
    provenance = json.load(stream, object_pairs_hook=no_duplicates)
paths = {
    "source_repository": ("source", "repository"),
    "source_commit": ("source", "commit"),
    "upstream_base_commit": ("source", "upstreamBaseCommit"),
    "source_version": ("build", "ghosttyVersion"),
    "build_revision": ("build", "revision"),
    "zig_version": ("build", "zigVersion"),
    "zig_archive_sha256": ("build", "zigArchiveSha256"),
    "xcframework_target": ("build", "target"),
    "optimize": ("build", "optimize"),
    "build_mode": ("build", "buildMode"),
    "minimum_ios_major": ("build", "minimumIOSMajor"),
    "framework_tree_sha256": ("artifact", "frameworkTreeSha256"),
}
try:
    parent, child = paths[key]
    value = provenance[parent][child]
except (KeyError, TypeError, DuplicateKey) as error:
    raise SystemExit(f"invalid provenance: {error}")
if isinstance(value, bool) or not isinstance(value, (str, int)):
    raise SystemExit("invalid provenance value")
print(value)
PY
        return
    fi

    local value count
    count="$(awk -F= -v key="$key" '$1 == key { count += 1; value = substr($0, length(key) + 2) } END { print count }' "$provenance_path")"
    [[ "$count" == "1" ]] || fail "provenance is missing or duplicates $key"
    value="$(awk -F= -v key="$key" '$1 == key { print substr($0, length(key) + 2); exit }' "$provenance_path")"
    printf '%s\n' "$value"
}

[[ "$(read_provenance source_repository)" == "$MORI_GHOSTTYKIT_SOURCE_REPOSITORY" ]] || fail "unexpected source repository"
[[ "$(read_provenance source_commit)" == "$MORI_GHOSTTYKIT_SOURCE_COMMIT" ]] || fail "unexpected source commit"
[[ "$(read_provenance upstream_base_commit)" == "$MORI_GHOSTTYKIT_BASE_COMMIT" ]] || fail "unexpected upstream base commit"
[[ "$(read_provenance source_version)" == "$MORI_GHOSTTYKIT_VERSION" ]] || fail "unexpected explicit source version"
[[ "$(read_provenance build_revision)" == "$MORI_GHOSTTYKIT_BUILD_REVISION" ]] || fail "unexpected build revision"
[[ "$(read_provenance zig_version)" == "$MORI_GHOSTTYKIT_ZIG_VERSION" ]] || fail "unexpected Zig version"
[[ "$(read_provenance zig_archive_sha256)" == "$MORI_GHOSTTYKIT_ZIG_ARCHIVE_SHA256" ]] || fail "unexpected Zig archive digest"
[[ "$(read_provenance xcframework_target)" == "$MORI_GHOSTTYKIT_TARGET" ]] || fail "artifact was not built with the locked target"
[[ "$(read_provenance optimize)" == "$MORI_GHOSTTYKIT_OPTIMIZE" ]] || fail "unexpected optimization mode"
[[ "$(read_provenance build_mode)" == "$MORI_GHOSTTYKIT_BUILD_MODE" ]] || fail "unexpected build mode provenance"
[[ "$(read_provenance minimum_ios_major)" == "$MORI_GHOSTTYKIT_MIN_IOS_MAJOR" ]] || fail "unexpected minimum iOS provenance"

provenance_tree_sha256="$(read_provenance framework_tree_sha256)"
[[ "$provenance_tree_sha256" =~ ^[0-9a-f]{64}$ ]] || fail "missing framework content digest"
actual_tree_sha256="$(ghosttykit_framework_tree_sha256 "$xcframework")" || fail "unsafe framework tree"
[[ "$actual_tree_sha256" == "$provenance_tree_sha256" ]] || fail "framework files do not match the provenance content digest"
if [[ "$MORI_GHOSTTYKIT_ARTIFACT_STATE" == "published" ]]; then
    [[ "$actual_tree_sha256" == "$MORI_GHOSTTYKIT_FRAMEWORK_TREE_SHA256" ]] || \
        fail "framework files do not match the final lock digest"
fi

# Source builders validate the checkout before producing this artifact. Consumers
# need only the reviewed lock, provenance, and bytes; they may not clone the source.
if [[ "${MORI_GHOSTTYKIT_VERIFY_SOURCE:-0}" == "1" ]]; then
    ghosttykit_validate_source "$repo_root" || fail "source checkout does not match the lock"
fi

# This release must support macOS plus the locked iOS device and simulator SDKs.
for slice in macos-arm64_x86_64 ios-arm64 ios-arm64-simulator; do
    headers="$xcframework/$slice/Headers"
    [[ -f "$headers/ghostty.h" ]] || fail "missing $slice header"
    [[ -f "$headers/module.modulemap" ]] || fail "missing $slice module map"
done

macos_library="$xcframework/macos-arm64_x86_64/libghostty-internal-fat.a"
[[ -f "$macos_library" ]] || fail "missing macOS static library"
[[ "$(lipo -archs "$macos_library")" == *"arm64"* && "$(lipo -archs "$macos_library")" == *"x86_64"* ]] || fail "macOS slice is not universal"

for slice in ios-arm64 ios-arm64-simulator; do
    library="$xcframework/$slice/libghostty-internal-fat.a"
    [[ -f "$library" ]] || fail "missing $slice static library"
    [[ "$(lipo -archs "$library")" == *"arm64"* ]] || fail "$slice lacks arm64"
done

plist_xml="$(plutil -extract AvailableLibraries xml1 -o - "$xcframework/Info.plist")"
printf '%s' "$plist_xml" | grep -q '<string>macos-arm64_x86_64</string>' || fail "missing macOS metadata"
printf '%s' "$plist_xml" | grep -q '<string>ios-arm64</string>' || fail "missing ios-arm64 metadata"
printf '%s' "$plist_xml" | grep -q '<string>ios-arm64-simulator</string>' || fail "missing ios-arm64-simulator metadata"
printf '%s' "$plist_xml" | grep -q '<string>simulator</string>' || fail "missing simulator platform variant"

probe_source="$(mktemp "${TMPDIR:-/tmp}/mori-ghosttykit-abi.XXXXXX.c")"
trap 'rm -f "$probe_source" "${probe_source%.c}".*' EXIT
cat >"$probe_source" <<'SOURCE'
#include <ghostty.h>
int remux_tmux_abi_probe(void) {
    ghostty_tmux_client_config_s config = ghostty_tmux_client_config_new();
    return (int)config.initial_columns + (int)ghostty_info().build_mode;
}
SOURCE
for sdk in iphoneos iphonesimulator; do
    sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
    slice="ios-arm64"
    target="arm64-apple-ios${MORI_GHOSTTYKIT_MIN_IOS_MAJOR}.0"
    if [[ "$sdk" == "iphonesimulator" ]]; then
        slice="ios-arm64-simulator"
        target="arm64-apple-ios${MORI_GHOSTTYKIT_MIN_IOS_MAJOR}.0-simulator"
    fi
    xcrun --sdk "$sdk" clang -target "$target" \
        -isysroot "$sdk_path" -fmodules -I "$xcframework/$slice/Headers" \
        -c "$probe_source" -o "${probe_source%.c}.$sdk.o"
done

# The iOS binaries cannot execute on the build host. The macOS slice supplies
# the runnable optimization-mode gate for the same universal artifact.
macos_probe="${probe_source%.c}.macos"
xcrun --sdk macosx clang -target "$(uname -m)-apple-macos15.0" \
    -I "$xcframework/macos-arm64_x86_64/Headers" -x c - -x none "$macos_library" \
    -lc++ -framework Foundation -framework AppKit -framework Metal \
    -framework QuartzCore -framework IOSurface -framework Carbon -o "$macos_probe" <<'SOURCE'
#include <stdio.h>
#include <ghostty.h>
int main(void) { printf("%d\n", (int)ghostty_info().build_mode); }
SOURCE
[[ "$("$macos_probe")" == "$MORI_GHOSTTYKIT_BUILD_MODE" ]] || fail "artifact has an unexpected build mode"

for library in "$macos_library" "$xcframework/ios-arm64/libghostty-internal-fat.a" "$xcframework/ios-arm64-simulator/libghostty-internal-fat.a"; do
    symbols="$(nm -gU "$library")"
    for symbol in _ghostty_info _ghostty_tmux_client_config_new _ghostty_tmux_client_new _ghostty_tmux_client_feed _ghostty_tmux_client_outbound _ghostty_tmux_client_consume; do
        grep -q "${symbol}$" <<<"$symbols" || fail "$(basename "$(dirname "$library")") lacks $symbol"
    done
done

for slice in ios-arm64 ios-arm64-simulator; do
    minos_values="$(otool -l "$xcframework/$slice/libghostty-internal-fat.a" | awk '/minos / { print $2 }' | sort -u)"
    [[ -n "$minos_values" ]] || fail "$slice has no LC_BUILD_VERSION minimum OS metadata"
    while IFS= read -r minos; do
        major="${minos%%.*}"
        [[ "$major" =~ ^[0-9]+$ && "$major" -le "$MORI_GHOSTTYKIT_MIN_IOS_MAJOR" ]] || \
            fail "$slice requires iOS $minos, above the lock contract"
    done <<<"$minos_values"
done

printf 'Verified locked GhosttyKit %s: universal macOS, iOS %s device/simulator arm64 slices, and remux tmux ABI.\n' \
    "$MORI_GHOSTTYKIT_SOURCE_COMMIT" "$MORI_GHOSTTYKIT_MIN_IOS_MAJOR"
