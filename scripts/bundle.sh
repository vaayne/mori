#!/bin/bash
set -euo pipefail

APP_NAME="Mori"
BUNDLE_ID="dev.mori.app"
APP_BUILD_DIR=".build/release"
CLI_BUILD_DIR=".build-cli/release"
APP_BUNDLE="${APP_NAME}.app"
MORI_VERSION="${MORI_VERSION:-0.1.0}"

# Build app and CLI separately. "Mori" and "mori" collide on the default
# case-insensitive macOS filesystem, so the CLI uses a dedicated build path.
swift build -c release --product Mori 2>&1 | xcbeautify
swift build --build-path .build-cli -c release --product mori 2>&1 | xcbeautify

# Create .app structure
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/MacOS/bin"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$APP_BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$CLI_BUILD_DIR/mori" "$APP_BUNDLE/Contents/MacOS/bin/mori"

# Copy app icon
cp "assets/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

copy_resource_bundles() {
    local build_dir="$1"
    for bundle in "$build_dir"/*.bundle; do
        if [[ -d "$bundle" ]]; then
            local target="$APP_BUNDLE/Contents/Resources/$(basename "$bundle")"
            rm -rf "$target"
            ditto --norsrc "$bundle" "$target"
            find "$target" -name "._*" -delete 2>/dev/null || true
            echo "   Bundled: $(basename "$bundle")"
        fi
    done
}

# Copy SPM resource bundles into Contents/Resources/ so the packaged app and
# runtime bundle lookup use the same app bundle layout in local and CI builds.
copy_resource_bundles "$APP_BUILD_DIR"
copy_resource_bundles "$CLI_BUILD_DIR"

# Copy ghostty resources (terminfo sentinel + themes) so libghostty can resolve
# its resources_dir from the app bundle. Ghostty walks up from the executable
# looking for Contents/Resources/terminfo/78/xterm-ghostty as a sentinel.
GHOSTTY_RESOURCES="Frameworks/ghostty-resources"
if [[ -d "$GHOSTTY_RESOURCES" ]]; then
    ditto "$GHOSTTY_RESOURCES" "$APP_BUNDLE/Contents/Resources/"
    echo "   Ghostty resources bundled (themes, terminfo, shell-integration)"
else
    echo "⚠️  Warning: $GHOSTTY_RESOURCES not found. Run 'mise run build:ghostty' first."
    echo "   Theme resolution will not work in the bundled app."
fi

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>${MORI_VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${MORI_VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

# Sign if SIGNING_IDENTITY is set
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    SIGN_ARGS=()
    if [[ -n "${KEYCHAIN_PROFILE:-}" ]]; then
        SIGN_ARGS+=(--notarize)
    fi
    bash scripts/sign.sh "${SIGN_ARGS[@]}"
fi

# In CI, keep the bundle in the working directory for archiving
if [[ -z "${CI:-}" ]]; then
    # Quit the app if it's running
    pkill -x "$APP_NAME" 2>/dev/null && sleep 1 || true

    # Move to /Applications
    rm -rf "/Applications/$APP_BUNDLE"
    mv "$APP_BUNDLE" "/Applications/$APP_BUNDLE"

    echo "✅ Built and installed to /Applications/$APP_BUNDLE"
    echo "   Run with: open /Applications/$APP_BUNDLE"
else
    echo "✅ Built $APP_BUNDLE (CI mode — kept in working directory)"
fi
