#!/usr/bin/env bash
# Build GhosttyKit XCFramework from Ghostty source.
# Requires: zig 0.15.2 (installed via mise)
#
# Usage: bash scripts/build-ghostty.sh [--clean] [--universal]
#   default: native macOS slice only
#   --universal: build macOS + iOS device + iOS simulator slices
#                requires Xcode.app with iOS SDKs installed
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=ghosttykit-contract.sh
source "$PROJECT_ROOT/scripts/ghosttykit-contract.sh"
GHOSTTY_DIR="$PROJECT_ROOT/vendor/ghostty"
FRAMEWORK_DIR="$PROJECT_ROOT/Frameworks"
XCFRAMEWORK="$FRAMEWORK_DIR/GhosttyKit.xcframework"
RESOURCES_DIR="$FRAMEWORK_DIR/ghostty-resources"

repo_slug() {
    local remote_url
    remote_url="$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null || true)"
    case "$remote_url" in
        https://github.com/*)
            remote_url="${remote_url#https://github.com/}"
            remote_url="${remote_url%.git}"
            ;;
        git@github.com:*)
            remote_url="${remote_url#git@github.com:}"
            remote_url="${remote_url%.git}"
            ;;
        *)
            return 1
            ;;
    esac
    printf '%s\n' "$remote_url"
}

find_matching_ci_run() {
    command -v gh >/dev/null 2>&1 || return 1

    local repo ghostty_sha runs_json run_id run_sha run_ghostty_sha
    repo="$(repo_slug)" || return 1
    ghostty_sha="$(git -C "$GHOSTTY_DIR" rev-parse HEAD)"
    runs_json="$(gh run list --repo "$repo" --workflow CI --branch main --status success --limit 20 --json databaseId,headSha 2>/dev/null)" || return 1

    while IFS=$'\t' read -r run_id run_sha; do
        [[ -n "$run_id" && -n "$run_sha" ]] || continue
        run_ghostty_sha="$(gh api "repos/$repo/contents/vendor/ghostty?ref=$run_sha" --jq '.sha' 2>/dev/null || true)"
        if [[ "$run_ghostty_sha" == "$ghostty_sha" ]]; then
            printf '%s\n' "$run_id"
            return 0
        fi
    done < <(printf '%s' "$runs_json" | jq -r '.[] | [.databaseId, .headSha] | @tsv')

    return 1
}

restore_ci_artifact() {
    command -v gh >/dev/null 2>&1 || return 1

    local repo run_id tmp_dir
    repo="$(repo_slug)" || return 1
    run_id="$(find_matching_ci_run)" || return 1
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' RETURN

    echo "Downloading GhosttyKit artifact from CI run $run_id..."
    gh run download "$run_id" --repo "$repo" -n GhosttyKit -D "$tmp_dir" >/dev/null

    [[ -f "$tmp_dir/GhosttyKit.xcframework/Info.plist" ]] || return 1
    [[ -d "$tmp_dir/ghostty-resources" ]] || return 1
    [[ -f "$tmp_dir/.ghosttykit-provenance" ]] || return 1

    mkdir -p "$FRAMEWORK_DIR"
    rm -rf "$XCFRAMEWORK" "$RESOURCES_DIR" "$FRAMEWORK_DIR/.ghosttykit-provenance"
    cp -R "$tmp_dir/GhosttyKit.xcframework" "$XCFRAMEWORK"
    cp -R "$tmp_dir/ghostty-resources" "$RESOURCES_DIR"
    cp "$tmp_dir/.ghosttykit-provenance" "$FRAMEWORK_DIR/.ghosttykit-provenance"

    if [[ "$UNIVERSAL" == true ]]; then
        MORI_GHOSTTYKIT_XCFRAMEWORK="$XCFRAMEWORK" bash "$PROJECT_ROOT/scripts/verify-ghosttykit.sh" || return 1
    fi

    echo "Restored GhosttyKit.xcframework from CI artifact into $FRAMEWORK_DIR"
}

has_valid_xcframework() {
    [[ -f "$XCFRAMEWORK/Info.plist" ]] || return 1
    local static_lib
    static_lib="$(find "$XCFRAMEWORK" -type f -name "*.a" -print -quit 2>/dev/null || true)"
    [[ -n "$static_lib" ]]
}

normalize_universal_xcframework() {
    local macos_slice="$XCFRAMEWORK/macos-arm64_x86_64"
    local canonical_library="libghostty-internal-fat.a"
    [[ -d "$macos_slice" ]] || return 0

    if [[ -f "$macos_slice/ghostty-internal.a" ]]; then
        mv "$macos_slice/ghostty-internal.a" "$macos_slice/$canonical_library"
    fi
    [[ -f "$macos_slice/$canonical_library" ]] || {
        echo "Universal GhosttyKit is missing its macOS static library." >&2
        return 1
    }

    /usr/bin/python3 - "$XCFRAMEWORK/Info.plist" "$canonical_library" <<'PY'
import plistlib
import sys

path, library_name = sys.argv[1:]
with open(path, "rb") as stream:
    plist = plistlib.load(stream)
for library in plist.get("AvailableLibraries", []):
    if library.get("LibraryIdentifier") == "macos-arm64_x86_64":
        library["BinaryPath"] = library_name
        library["LibraryPath"] = library_name
        break
else:
    raise SystemExit("Universal GhosttyKit is missing macOS metadata")
with open(path, "wb") as stream:
    plistlib.dump(plist, stream, fmt=plistlib.FMT_XML, sort_keys=False)
PY
}

framework_tree_sha256() {
    local root="$1"
    find "$root" -type f -print0 | LC_ALL=C sort -z | while IFS= read -r -d '' file; do
        printf '%s  %s\n' "$(shasum -a 256 "$file" | awk '{print $1}')" "${file#"$root"/}"
    done | shasum -a 256 | awk '{print $1}'
}

write_provenance() {
    local target="$1"
    cat >"$FRAMEWORK_DIR/.ghosttykit-provenance" <<EOF
source_commit=$MORI_GHOSTTYKIT_SOURCE_COMMIT
source_version=$MORI_GHOSTTYKIT_VERSION
xcframework_target=$target
optimize=$MORI_GHOSTTYKIT_OPTIMIZE
framework_tree_sha256=$(framework_tree_sha256 "$XCFRAMEWORK")
EOF
}

has_matching_provenance() {
    [[ -f "$FRAMEWORK_DIR/.ghosttykit-provenance" ]] || return 1
    local source source_version target optimize expected_digest actual_digest
    source="$(awk -F= '$1 == "source_commit" { print substr($0, 15); exit }' "$FRAMEWORK_DIR/.ghosttykit-provenance")"
    source_version="$(awk -F= '$1 == "source_version" { print substr($0, 16); exit }' "$FRAMEWORK_DIR/.ghosttykit-provenance")"
    target="$(awk -F= '$1 == "xcframework_target" { print substr($0, 20); exit }' "$FRAMEWORK_DIR/.ghosttykit-provenance")"
    optimize="$(awk -F= '$1 == "optimize" { print substr($0, 10); exit }' "$FRAMEWORK_DIR/.ghosttykit-provenance")"
    expected_digest="$(awk -F= '$1 == "framework_tree_sha256" { print substr($0, 23); exit }' "$FRAMEWORK_DIR/.ghosttykit-provenance")"
    [[ "$source" == "$MORI_GHOSTTYKIT_SOURCE_COMMIT" && "$source_version" == "$MORI_GHOSTTYKIT_VERSION" && "$optimize" == "$MORI_GHOSTTYKIT_OPTIMIZE" ]] || return 1
    if [[ "$UNIVERSAL" == true ]]; then
        [[ "$target" == "universal" ]] || return 1
    else
        [[ "$target" == "native" || "$target" == "universal" ]] || return 1
    fi
    [[ "$expected_digest" =~ ^[0-9a-f]{64}$ ]] || return 1
    actual_digest="$(framework_tree_sha256 "$XCFRAMEWORK")"
    [[ "$actual_digest" == "$expected_digest" ]]
}

# Strip archive debug symbols to avoid dsymutil warnings caused by duplicate
# object basenames inside libghostty-fat.a (e.g. multiple ext.o members).
strip_archive_debug_symbols() {
    local xcframework_path="$1"
    while IFS= read -r -d '' archive; do
        /usr/bin/strip -S "$archive" 2>/dev/null || true
    done < <(find "$xcframework_path" -type f -name "*.a" -print0)
}

CLEAN=false
UNIVERSAL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean)
            CLEAN=true
            ;;
        --universal)
            UNIVERSAL=true
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: bash scripts/build-ghostty.sh [--clean] [--universal]"
            exit 1
            ;;
    esac
    shift
done

if [[ "$CLEAN" == true ]]; then
    echo "Cleaning Ghostty build artifacts..."
    rm -rf "$XCFRAMEWORK" "$RESOURCES_DIR" "$FRAMEWORK_DIR/.ghosttykit-provenance"
fi

# Check submodule is initialized
if [[ ! -f "$GHOSTTY_DIR/build.zig" ]]; then
    echo "Initializing ghostty submodule..."
    git -C "$PROJECT_ROOT" submodule update --init vendor/ghostty
fi

[[ "$(git -C "$GHOSTTY_DIR" rev-parse HEAD)" == "$MORI_GHOSTTYKIT_SOURCE_COMMIT" ]] || {
    echo "Ghostty source does not match the pinned remux commit $MORI_GHOSTTYKIT_SOURCE_COMMIT." >&2
    exit 1
}
git -C "$GHOSTTY_DIR" diff --quiet || {
    echo "Ghostty source has tracked modifications; refusing to build an unverifiable framework." >&2
    exit 1
}
grep -Fq ".version = \"$MORI_GHOSTTYKIT_VERSION\"" "$GHOSTTY_DIR/build.zig.zon" || {
    echo "Pinned Ghostty version no longer matches build.zig.zon." >&2
    exit 1
}

# Fail closed on a stale or altered local framework before deciding it can be reused.
if has_valid_xcframework && [[ -d "$RESOURCES_DIR" ]] && ! has_matching_provenance; then
    echo "Cached GhosttyKit provenance does not match the pinned source; rebuilding..." >&2
    rm -rf "$XCFRAMEWORK" "$FRAMEWORK_DIR/.ghosttykit-provenance"
fi

# Skip if already built and has the required slices
if has_valid_xcframework && [[ -d "$RESOURCES_DIR" ]]; then
    # Validate that cached xcframework has required slices for requested mode
    local_needs_rebuild=false
    if [[ "$UNIVERSAL" == true ]]; then
        for slice in ios-arm64 ios-arm64-simulator; do
            if [[ ! -d "$XCFRAMEWORK/$slice" ]]; then
                echo "Cached xcframework missing $slice slice (needed for --universal); rebuilding..."
                local_needs_rebuild=true
                break
            fi
        done
    fi
    if [[ "$local_needs_rebuild" == false && "$UNIVERSAL" == true ]]; then
        if ! MORI_GHOSTTYKIT_XCFRAMEWORK="$XCFRAMEWORK" bash "$PROJECT_ROOT/scripts/verify-ghosttykit.sh"; then
            echo "Cached universal GhosttyKit failed verification; rebuilding..." >&2
            local_needs_rebuild=true
        fi
    fi
    if [[ "$local_needs_rebuild" == false ]]; then
        echo "GhosttyKit.xcframework and resources already exist at $FRAMEWORK_DIR"
        echo "Run with --clean to rebuild."
        exit 0
    fi
    rm -rf "$XCFRAMEWORK" "$FRAMEWORK_DIR/.ghosttykit-provenance"
fi

if [[ -d "$XCFRAMEWORK" ]] && ! has_valid_xcframework; then
    echo "Found invalid GhosttyKit.xcframework at $XCFRAMEWORK; rebuilding..."
    rm -rf "$XCFRAMEWORK"
fi

# A source-pinned framework must carry matching source-pinned resources; never
# leave resources from an invalidated cache beside a newly built library.
rm -rf "$RESOURCES_DIR"

# Verify zig is available
if ! command -v zig &>/dev/null; then
    echo "Error: zig not found. Run 'mise install' first."
    exit 1
fi

ZIG_VERSION=$(zig version)
echo "Using Zig $ZIG_VERSION"

cd "$GHOSTTY_DIR"

if ! xcrun -sdk macosx --find metal >/dev/null 2>&1; then
    echo "Metal toolchain not found. Installing with xcodebuild..."
    xcodebuild -downloadComponent MetalToolchain
fi

XCFW_TARGET="native"
if [[ "$UNIVERSAL" == true ]]; then
    XCFW_TARGET="universal"
    if ! xcrun -sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
        echo "Error: --universal requires Xcode.app with the iPhoneOS SDK installed."
        exit 1
    fi
    if ! xcrun -sdk iphonesimulator --show-sdk-path >/dev/null 2>&1; then
        echo "Error: --universal requires Xcode.app with the iPhoneSimulator SDK installed."
        exit 1
    fi
else
    # Patch: skip iOS/iOS Simulator builds when using native target.
    # Ghostty's GhosttyXCFramework.zig eagerly initializes iOS targets even
    # when xcframework-target=native. This fails without Xcode.app (needs iphoneos SDK).
    # The patch moves iOS init inside the universal branch only.
    XCFW_ZIG="$GHOSTTY_DIR/src/build/GhosttyXCFramework.zig"
    restore_native_patch() {
        if grep -q "MORI_PATCHED" "$XCFW_ZIG" 2>/dev/null; then
            git -C "$GHOSTTY_DIR" checkout -- src/build/GhosttyXCFramework.zig >/dev/null 2>&1 || true
        fi
    }
    trap restore_native_patch EXIT

    if ! grep -q "MORI_PATCHED" "$XCFW_ZIG" 2>/dev/null; then
        echo "Applying native-only build patch..."
        cat > "$XCFW_ZIG" <<'ZIGEOF'
// MORI_PATCHED: skip iOS builds for native-only target
const GhosttyXCFramework = @This();

const std = @import("std");
const Config = @import("Config.zig");
const SharedDeps = @import("SharedDeps.zig");
const GhosttyLib = @import("GhosttyLib.zig");
const XCFrameworkStep = @import("XCFrameworkStep.zig");
const Target = @import("xcframework.zig").Target;

xcframework: *XCFrameworkStep,
target: Target,

pub fn init(
    b: *std.Build,
    deps: *const SharedDeps,
    target: Target,
) !GhosttyXCFramework {
    // Generate a headers directory with only ghostty.h and the module
    // map. We can't use include/ directly because it also contains the
    // libghostty-vt headers under include/ghostty/, which would trigger
    // "umbrella header does not include header" warnings from Clang's
    // module system.
    const wf = b.addWriteFiles();
    _ = wf.addCopyFile(b.path("include/ghostty.h"), "ghostty.h");
    _ = wf.addCopyFile(b.path("include/module.modulemap"), "module.modulemap");
    const headers = wf.getDirectory();

    const xcframework = switch (target) {
        .universal => blk: {
            const macos_universal = try GhosttyLib.initMacOSUniversal(b, deps);
            const ios = try GhosttyLib.initStatic(b, &try deps.retarget(
                b,
                b.resolveTargetQuery(.{
                    .cpu_arch = .aarch64,
                    .os_tag = .ios,
                    .os_version_min = Config.osVersionMin(.ios),
                    .abi = null,
                }),
            ));
            const ios_sim = try GhosttyLib.initStatic(b, &try deps.retarget(
                b,
                b.resolveTargetQuery(.{
                    .cpu_arch = .aarch64,
                    .os_tag = .ios,
                    .os_version_min = Config.osVersionMin(.ios),
                    .abi = .simulator,
                    .cpu_model = .{ .explicit = &std.Target.aarch64.cpu.apple_a17 },
                }),
            ));
            break :blk XCFrameworkStep.create(b, .{
                .name = "GhosttyKit",
                .out_path = "macos/GhosttyKit.xcframework",
                .libraries = &.{
                    .{
                        .library = macos_universal.output,
                        .headers = headers,
                        .dsym = macos_universal.dsym,
                    },
                    .{
                        .library = ios.output,
                        .headers = headers,
                        .dsym = ios.dsym,
                    },
                    .{
                        .library = ios_sim.output,
                        .headers = headers,
                        .dsym = ios_sim.dsym,
                    },
                },
            });
        },
        .native => blk: {
            const macos_native = try GhosttyLib.initStatic(b, &try deps.retarget(
                b,
                Config.genericMacOSTarget(b, null),
            ));
            break :blk XCFrameworkStep.create(b, .{
                .name = "GhosttyKit",
                .out_path = "macos/GhosttyKit.xcframework",
                .libraries = &.{.{
                    .library = macos_native.output,
                    .headers = headers,
                    .dsym = macos_native.dsym,
                }},
            });
        },
    };

    return .{
        .xcframework = xcframework,
        .target = target,
    };
}

pub fn install(self: *const GhosttyXCFramework) void {
    const b = self.xcframework.step.owner;
    self.addStepDependencies(b.getInstallStep());
}

pub fn addStepDependencies(
    self: *const GhosttyXCFramework,
    other_step: *std.Build.Step,
) void {
    other_step.dependOn(self.xcframework.step);
}
ZIGEOF
        echo "Patch applied."
    fi
fi

# Clear zig build cache to pick up patched file
rm -rf "$GHOSTTY_DIR/.zig-cache"

# Build XCFramework
BUILD_LOG="$(mktemp)"
echo "Building GhosttyKit XCFramework target=$XCFW_TARGET (this may take a few minutes)..."
if ! zig build \
    -Demit-xcframework=true \
    -Demit-macos-app=false \
    -Dxcframework-target="$XCFW_TARGET" \
    -Dapp-runtime=none \
    -Dversion-string="$MORI_GHOSTTYKIT_VERSION" \
    -Doptimize=ReleaseFast \
    2> >(tee "$BUILD_LOG" >&2); then
    if grep -q "undefined symbol: __availability_version_check" "$BUILD_LOG"; then
        echo "Detected Zig 0.15.x linker incompatibility with the local macOS toolchain."
        if restore_ci_artifact; then
            exit 0
        fi
        echo "CI artifact fallback was unavailable; keeping the original Zig build failure." >&2
    fi
    exit 1
fi
rm -f "$BUILD_LOG"

# Find the built XCFramework
BUILD_OUTPUT="$GHOSTTY_DIR/zig-out/GhosttyKit.xcframework"
if [[ ! -d "$BUILD_OUTPUT" ]]; then
    # Check alternate output location
    BUILD_OUTPUT="$GHOSTTY_DIR/macos/GhosttyKit.xcframework"
fi
if [[ ! -d "$BUILD_OUTPUT" ]]; then
    echo "Error: XCFramework not found"
    echo "Checking zig-out contents:"
    find "$GHOSTTY_DIR/zig-out/" -name "*.xcframework" -type d 2>/dev/null || echo "(no xcframework found)"
    ls -la "$GHOSTTY_DIR/zig-out/" 2>/dev/null || echo "(zig-out not found)"
    exit 1
fi

# Copy XCFramework to project Frameworks directory
mkdir -p "$FRAMEWORK_DIR"
rm -rf "$XCFRAMEWORK" "$FRAMEWORK_DIR/.ghosttykit-provenance"
cp -R "$BUILD_OUTPUT" "$XCFRAMEWORK"
if [[ "$UNIVERSAL" == true ]]; then
    normalize_universal_xcframework
fi
strip_archive_debug_symbols "$XCFRAMEWORK"
write_provenance "$XCFW_TARGET"

if [[ "$UNIVERSAL" == true ]]; then
    MORI_GHOSTTYKIT_XCFRAMEWORK="$XCFRAMEWORK" bash "$PROJECT_ROOT/scripts/verify-ghosttykit.sh"
fi

echo "GhosttyKit.xcframework built successfully at $XCFRAMEWORK"
# Show module map to confirm structure
find "$XCFRAMEWORK" -name "module.modulemap" -exec echo "Module map:" \; -exec cat {} \; 2>/dev/null || true

# Copy resources (terminfo + themes + shell-integration) for app bundling
SHARE_DIR="$GHOSTTY_DIR/zig-out/share"
if [[ -d "$SHARE_DIR" ]]; then
    rm -rf "$RESOURCES_DIR"
    mkdir -p "$RESOURCES_DIR"
    cp -R "$SHARE_DIR/"* "$RESOURCES_DIR/"
    echo "Ghostty resources copied to $RESOURCES_DIR"
    echo "  themes: $(ls "$RESOURCES_DIR/ghostty/themes/" 2>/dev/null | wc -l | tr -d ' ') files"
else
    echo "Warning: zig-out/share not found — resources not copied."
    echo "Theme resolution may not work in bundled .app builds."
fi
