#!/bin/bash
# Sign and optionally notarize Mori.app
# Usage:
#   scripts/sign.sh [--notarize]
#
# Environment variables:
#   SIGNING_IDENTITY   — Developer ID Application identity (required)
#   ENTITLEMENTS       — Path to entitlements file (default: Mori.entitlements)
#   KEYCHAIN_PROFILE   — notarytool keychain profile name (required for --notarize)
#   APP_BUNDLE         — Path to .app bundle (default: Mori.app)
set -euo pipefail

NOTARIZE=false
for arg in "$@"; do
    case "$arg" in
        --notarize) NOTARIZE=true ;;
        *) echo "Unknown argument: $arg"; exit 1 ;;
    esac
done

APP_BUNDLE="${APP_BUNDLE:-Mori.app}"
ENTITLEMENTS="${ENTITLEMENTS:-Mori.entitlements}"

if [[ -z "${SIGNING_IDENTITY:-}" ]]; then
    echo "❌ SIGNING_IDENTITY is not set"
    echo "   Set it to your Developer ID Application identity, e.g.:"
    echo "   export SIGNING_IDENTITY=\"Developer ID Application: Your Name (TEAM_ID)\""
    exit 1
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "❌ $APP_BUNDLE not found. Run 'mise run bundle' first."
    exit 1
fi

if [[ ! -f "$ENTITLEMENTS" ]]; then
    echo "❌ Entitlements file not found: $ENTITLEMENTS"
    exit 1
fi

echo "🔏 Signing $APP_BUNDLE with identity: $SIGNING_IDENTITY"

# Remove any ._ AppleDouble files that would invalidate the seal
find "$APP_BUNDLE" -name "._*" -delete 2>/dev/null || true

# Sign embedded frameworks and dylibs first (inside-out signing)
if [[ -d "$APP_BUNDLE/Contents/Frameworks" ]]; then
    find "$APP_BUNDLE/Contents/Frameworks" \( -name "*.dylib" -o -name "*.framework" \) -print0 | while IFS= read -r -d '' item; do
        echo "   Signing: $(basename "$item")"
        codesign --force --options runtime --timestamp \
            --sign "$SIGNING_IDENTITY" \
            "$item"
    done
fi

# Sign XPC services (inside-out — must be signed before the main app)
if [[ -d "$APP_BUNDLE/Contents/XPCServices" ]]; then
    find "$APP_BUNDLE/Contents/XPCServices" -name "*.xpc" -type d -print0 | while IFS= read -r -d '' item; do
        echo "   Signing XPC service: $(basename "$item")"
        codesign --force --options runtime --timestamp \
            --sign "$SIGNING_IDENTITY" \
            "$item"
    done
fi

# Sign resource bundles (inside-out — must be signed before the main app)
find "$APP_BUNDLE/Contents" -name "*.bundle" -type d -print0 | while IFS= read -r -d '' item; do
    echo "   Signing bundle: $(basename "$item")"
    codesign --force --options runtime --timestamp \
        --sign "$SIGNING_IDENTITY" \
        "$item"
done

# Sign helper executables if any
if [[ -d "$APP_BUNDLE/Contents/MacOS" ]]; then
    find "$APP_BUNDLE/Contents/MacOS" -type f -perm +111 ! -name "Mori" -print0 | while IFS= read -r -d '' item; do
        echo "   Signing helper: $(basename "$item")"
        codesign --force --options runtime --timestamp \
            --sign "$SIGNING_IDENTITY" \
            "$item"
    done
fi

# Sign the main app bundle
codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGNING_IDENTITY" \
    "$APP_BUNDLE"

echo "✅ Signed successfully"

# Verify signature
echo "🔍 Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
echo "✅ Signature verified"

# Notarize if requested
if [[ "$NOTARIZE" == "true" ]]; then
    if [[ -z "${KEYCHAIN_PROFILE:-}" ]]; then
        echo "❌ KEYCHAIN_PROFILE is not set (required for notarization)"
        echo "   Store credentials first:"
        echo "   xcrun notarytool store-credentials \"mori-notarize\" \\"
        echo "     --apple-id \"your@email.com\" \\"
        echo "     --team-id \"TEAM_ID\" \\"
        echo "     --password \"app-specific-password\""
        exit 1
    fi

    echo "📦 Creating zip for notarization..."
    NOTARIZE_ZIP="${APP_BUNDLE%.app}-notarize.zip"
    ditto -c -k --norsrc --keepParent "$APP_BUNDLE" "$NOTARIZE_ZIP"

    echo "🚀 Submitting for notarization..."
    xcrun notarytool submit "$NOTARIZE_ZIP" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait

    echo "📌 Stapling notarization ticket..."
    xcrun stapler staple "$APP_BUNDLE"

    # Clean up
    rm -f "$NOTARIZE_ZIP"

    echo "✅ Notarization complete"
fi
