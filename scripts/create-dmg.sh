#!/bin/bash
# Create a DMG installer from Mori.app
# Usage:
#   scripts/create-dmg.sh [version]
#
# Environment variables:
#   SIGNING_IDENTITY — signs the DMG if set
#   APP_BUNDLE       — path to .app (default: Mori.app)
set -euo pipefail

VERSION="${1:-0.1.0}"
APP_BUNDLE="${APP_BUNDLE:-Mori.app}"
DMG_NAME="Mori-${VERSION}-macos-arm64.dmg"
VOL_NAME="Mori"
STAGING_DIR="$(mktemp -d)"

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "❌ $APP_BUNDLE not found"
    exit 1
fi

echo "📦 Creating DMG: $DMG_NAME"

# Stage contents
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# Create DMG
hdiutil create \
    -volname "$VOL_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_NAME"

# Clean up staging
rm -rf "$STAGING_DIR"

# Sign the DMG if identity is available
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    echo "🔏 Signing DMG..."
    codesign --force --sign "$SIGNING_IDENTITY" "$DMG_NAME"
    echo "✅ DMG signed"
fi

echo "✅ Created $DMG_NAME"
