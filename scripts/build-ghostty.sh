#!/usr/bin/env bash
# Build GhosttyKit XCFramework from Ghostty source.
# Requires: zig 0.15.2 (installed via mise)
#
# Usage: bash scripts/build-ghostty.sh [--clean]
set -euo pipefail

GHOSTTY_COMMIT="c9e1006213eb9234209924c91285d6863e59ce4c"
GHOSTTY_DIR="${TMPDIR:-/tmp}/ghostty-build"
FRAMEWORK_DIR="$(cd "$(dirname "$0")/.." && pwd)/Frameworks"
XCFRAMEWORK="$FRAMEWORK_DIR/GhosttyKit.xcframework"

# Clean mode: remove cached clone and rebuilt
if [[ "${1:-}" == "--clean" ]]; then
    echo "Cleaning Ghostty build cache..."
    rm -rf "$GHOSTTY_DIR" "$XCFRAMEWORK"
fi

# Skip if already built
if [[ -d "$XCFRAMEWORK" ]]; then
    echo "GhosttyKit.xcframework already exists at $XCFRAMEWORK"
    echo "Run with --clean to rebuild."
    exit 0
fi

# Verify zig is available
if ! command -v zig &>/dev/null; then
    echo "Error: zig not found. Run 'mise install' first."
    exit 1
fi

ZIG_VERSION=$(zig version)
echo "Using Zig $ZIG_VERSION"

# Clone or update Ghostty
if [[ -d "$GHOSTTY_DIR/.git" ]]; then
    echo "Using existing Ghostty clone at $GHOSTTY_DIR"
    cd "$GHOSTTY_DIR"
    git fetch origin
    git checkout "$GHOSTTY_COMMIT"
else
    echo "Cloning Ghostty..."
    git clone https://github.com/ghostty-org/ghostty.git "$GHOSTTY_DIR"
    cd "$GHOSTTY_DIR"
    git checkout "$GHOSTTY_COMMIT"
fi

# Patch: skip iOS/iOS Simulator builds when using native target.
# Ghostty's GhosttyXCFramework.zig eagerly initializes iOS targets even
# when xcframework-target=native. This fails without Xcode.app (needs iphoneos SDK).
# The patch moves iOS init inside the universal branch only.
XCFW_ZIG="$GHOSTTY_DIR/src/build/GhosttyXCFramework.zig"
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

# Copy to project Frameworks directory
mkdir -p "$FRAMEWORK_DIR"
rm -rf "$XCFRAMEWORK"
cp -R "$BUILD_OUTPUT" "$XCFRAMEWORK"

echo "GhosttyKit.xcframework built successfully at $XCFRAMEWORK"
# Show module map to confirm structure
find "$XCFRAMEWORK" -name "module.modulemap" -exec echo "Module map:" \; -exec cat {} \; 2>/dev/null || true
