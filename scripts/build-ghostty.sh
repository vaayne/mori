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

    mkdir -p "$FRAMEWORK_DIR"
    rm -rf "$XCFRAMEWORK" "$RESOURCES_DIR"
    cp -R "$tmp_dir/GhosttyKit.xcframework" "$XCFRAMEWORK"
    cp -R "$tmp_dir/ghostty-resources" "$RESOURCES_DIR"
    strip_archive_debug_symbols "$XCFRAMEWORK"

    echo "Restored GhosttyKit.xcframework from CI artifact into $FRAMEWORK_DIR"
}

has_valid_xcframework() {
    [[ -f "$XCFRAMEWORK/Info.plist" ]] || return 1
    local static_lib
    static_lib="$(find "$XCFRAMEWORK" -type f -name "*.a" -print -quit 2>/dev/null || true)"
    [[ -n "$static_lib" ]]
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
    rm -rf "$XCFRAMEWORK" "$RESOURCES_DIR"
fi

# Check submodule is initialized
if [[ ! -f "$GHOSTTY_DIR/build.zig" ]]; then
    echo "Initializing ghostty submodule..."
    git -C "$PROJECT_ROOT" submodule update --init vendor/ghostty
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
    if [[ "$local_needs_rebuild" == false ]]; then
        strip_archive_debug_symbols "$XCFRAMEWORK"
        echo "GhosttyKit.xcframework and resources already exist at $FRAMEWORK_DIR"
        echo "Run with --clean to rebuild."
        exit 0
    fi
    rm -rf "$XCFRAMEWORK"
fi

if [[ -d "$XCFRAMEWORK" ]] && ! has_valid_xcframework; then
    echo "Found invalid GhosttyKit.xcframework at $XCFRAMEWORK; rebuilding..."
    rm -rf "$XCFRAMEWORK"
fi

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
                        .headers = b.path("include"),
                        .dsym = macos_universal.dsym,
                    },
                    .{
                        .library = ios.output,
                        .headers = b.path("include"),
                        .dsym = ios.dsym,
                    },
                    .{
                        .library = ios_sim.output,
                        .headers = b.path("include"),
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
                    .headers = b.path("include"),
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
rm -rf "$XCFRAMEWORK"
cp -R "$BUILD_OUTPUT" "$XCFRAMEWORK"
strip_archive_debug_symbols "$XCFRAMEWORK"

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
