#!/usr/bin/env bash
# Build GhosttyKit XCFramework from Ghostty source.
# Requires: zig 0.15.2 (installed via mise)
#
# Usage: bash scripts/build-ghostty.sh [--clean]
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GHOSTTY_DIR="$PROJECT_ROOT/vendor/ghostty"
FRAMEWORK_DIR="$PROJECT_ROOT/Frameworks"
XCFRAMEWORK="$FRAMEWORK_DIR/GhosttyKit.xcframework"
RESOURCES_DIR="$FRAMEWORK_DIR/ghostty-resources"

has_valid_xcframework() {
    [[ -f "$XCFRAMEWORK/Info.plist" ]] || return 1
    local static_lib
    static_lib="$(find "$XCFRAMEWORK" -type f -name "*.a" -print -quit 2>/dev/null || true)"
    [[ -n "$static_lib" ]]
}

# Clean mode: remove built artifacts
if [[ "${1:-}" == "--clean" ]]; then
    echo "Cleaning Ghostty build artifacts..."
    rm -rf "$XCFRAMEWORK" "$RESOURCES_DIR"
fi

# Check submodule is initialized
if [[ ! -f "$GHOSTTY_DIR/build.zig" ]]; then
    echo "Initializing ghostty submodule..."
    git -C "$PROJECT_ROOT" submodule update --init vendor/ghostty
fi

# Skip if already built
if has_valid_xcframework && [[ -d "$RESOURCES_DIR" ]]; then
    echo "GhosttyKit.xcframework and resources already exist at $FRAMEWORK_DIR"
    echo "Run with --clean to rebuild."
    exit 0
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
    cat > "$XCFW_ZIG" << 'ZIGEOF'
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

# Clear zig build cache to pick up patched file
rm -rf "$GHOSTTY_DIR/.zig-cache"

# Build XCFramework (native macOS only)
echo "Building GhosttyKit XCFramework (this may take a few minutes)..."
zig build \
    -Demit-xcframework=true \
    -Demit-macos-app=false \
    -Dxcframework-target=native \
    -Dapp-runtime=none \
    -Doptimize=ReleaseFast

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
