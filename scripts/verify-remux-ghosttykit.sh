#!/usr/bin/env bash
# Verify the pinned iOS GhosttyKit layout and the remux tmux C ABI.
set -euo pipefail

readonly RELEASE_TAG="ghosttykit-20260731"
readonly ARCHIVE_SHA256="e54ca81edf40721f72e87b5a5449746cd8fdcc877d5b0f284cdf2e34609f21f9"
readonly SOURCE_COMMIT="aeb8f73790946d9c9ad175b3dafaec9911ef36bb"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
xcframework="${REMUX_GHOSTTYKIT_XCFRAMEWORK:-$repo_root/Frameworks/RemuxGhosttyKit.xcframework}"
provenance_path="$(dirname "$xcframework")/.remux-ghosttykit-provenance"

fail() {
    echo "RemuxGhosttyKit verification failed: $*" >&2
    exit 1
}

[[ -f "$xcframework/Info.plist" ]] || fail "missing Info.plist at $xcframework"
[[ -f "$provenance_path" ]] || fail "missing provenance record at $provenance_path"

read_provenance() {
    local key="$1"
    awk -F= -v key="$key" '$1 == key { print substr($0, length(key) + 2); exit }' "$provenance_path"
}
[[ "$(read_provenance release_tag)" == "$RELEASE_TAG" ]] || fail "unexpected release tag"
[[ "$(read_provenance archive_sha256)" == "$ARCHIVE_SHA256" ]] || fail "unexpected archive checksum"
[[ "$(read_provenance source_commit)" == "$SOURCE_COMMIT" ]] || fail "unexpected source commit"

# This release must support iOS 17's device and Apple Silicon simulator SDKs.
for slice in ios-arm64 ios-arm64-simulator; do
    headers="$xcframework/$slice/Headers"
    library="$xcframework/$slice/libghostty-internal-fat.a"
    [[ -f "$headers/ghostty.h" ]] || fail "missing $slice header"
    [[ -f "$headers/module.modulemap" ]] || fail "missing $slice module map"
    [[ -f "$library" ]] || fail "missing $slice static library"
    [[ "$(lipo -archs "$library")" == *"arm64"* ]] || fail "$slice lacks arm64"

done

# XCFramework metadata must identify a device and an Apple Silicon simulator slice.
plist_xml="$(plutil -extract AvailableLibraries xml1 -o - "$xcframework/Info.plist")"
printf '%s' "$plist_xml" | grep -q '<string>ios-arm64</string>' || fail "missing ios-arm64 metadata"
printf '%s' "$plist_xml" | grep -q '<string>ios-arm64-simulator</string>' || fail "missing ios-arm64-simulator metadata"
printf '%s' "$plist_xml" | grep -q '<string>simulator</string>' || fail "missing simulator platform variant"

# Compiling these declarations for both SDKs catches header/API drift. Linking
# is verified by xcodebuild below, where Xcode selects the XCFramework slice.
probe_source="$(mktemp "${TMPDIR:-/tmp}/mori-remux-ghosttykit-abi.XXXXXX.c")"
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
    target="arm64-apple-ios17.0"
    if [[ "$sdk" == "iphonesimulator" ]]; then
        slice="ios-arm64-simulator"
        target="arm64-apple-ios17.0-simulator"
    fi
    xcrun --sdk "$sdk" clang -target "$target" \
        -isysroot "$sdk_path" -fmodules -I "$xcframework/$slice/Headers" \
        -c "$probe_source" -o "${probe_source%.c}.$sdk.o"
done

# The iOS binaries cannot execute on the build host. The co-packaged macOS
# slice gives the release-mode gate a runnable check for this exact asset.
macos_slice="$xcframework/macos-arm64_x86_64"
[[ -f "$macos_slice/Headers/ghostty.h" ]] || fail "missing macOS header for release-mode check"
[[ -f "$macos_slice/ghostty-internal.a" ]] || fail "missing macOS library for release-mode check"
macos_probe="${probe_source%.c}.macos"
xcrun --sdk macosx clang -target "$(uname -m)-apple-macos15.0" \
    -I "$macos_slice/Headers" -x c - -x none "$macos_slice/ghostty-internal.a" \
    -lc++ -framework Foundation -framework AppKit -framework Metal \
    -framework QuartzCore -framework IOSurface -framework Carbon -o "$macos_probe" <<'SOURCE'
#include <stdio.h>
#include <ghostty.h>
int main(void) { printf("%d\n", (int)ghostty_info().build_mode); }
SOURCE
[[ "$("$macos_probe")" == "2" ]] || fail "release asset is not Ghostty ReleaseFast (build mode 2)"

# Header declarations alone are insufficient; require the custom tmux symbols
# to be exported by both iOS static-library slices.
for slice in ios-arm64 ios-arm64-simulator; do
    library="$xcframework/$slice/libghostty-internal-fat.a"
    symbols="$(nm -gU "$library")"
    for symbol in _ghostty_info _ghostty_tmux_client_config_new _ghostty_tmux_client_new _ghostty_tmux_client_feed _ghostty_tmux_client_outbound _ghostty_tmux_client_consume; do
        grep -q "${symbol}$" <<<"$symbols" || fail "$slice lacks $symbol"
    done
done

# All iOS object files must declare a deployment target no newer than iOS 17.
# A static archive can contain many members, so accept only minos values <= 17.
for slice in ios-arm64 ios-arm64-simulator; do
    minos_values="$(otool -l "$xcframework/$slice/libghostty-internal-fat.a" | awk '/minos / { print $2 }' | sort -u)"
    [[ -n "$minos_values" ]] || fail "$slice has no LC_BUILD_VERSION minimum OS metadata"
    while IFS= read -r minos; do
        major="${minos%%.*}"
        [[ "$major" =~ ^[0-9]+$ && "$major" -le 17 ]] || fail "$slice requires iOS $minos, above the iOS 17 contract"
    done <<<"$minos_values"
done

printf 'Verified RemuxGhosttyKit %s: iOS device/simulator arm64 slices, iOS 17-compatible minimum OS, and remux tmux ABI.\n' "$RELEASE_TAG"
