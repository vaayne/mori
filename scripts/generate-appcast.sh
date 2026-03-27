#!/usr/bin/env bash
# generate-appcast.sh — Download Sparkle tools, sign a release archive,
# and generate an appcast.xml with EdDSA signatures.
#
# Usage:
#   SPARKLE_PRIVATE_KEY="..." scripts/generate-appcast.sh <version> /path/to/Mori-1.0.0-macos-arm64.zip
#
# Arguments:
#   version       Semantic version (e.g., 1.0.0) — used to construct the GitHub Release download URL
#   archive.zip   Path to the signed release archive
#
# Output:
#   appcast.xml in the current working directory.
#
# Requires:
#   - SPARKLE_PRIVATE_KEY env var (base64-encoded Ed25519 private key)
#   - curl, tar (for downloading Sparkle release)

set -euo pipefail

SPARKLE_VERSION="2.9.0"
SPARKLE_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"

# --- Validate inputs ---

if [[ $# -lt 2 ]]; then
  echo "Usage: SPARKLE_PRIVATE_KEY=\"...\" $0 <version> /path/to/archive.zip" >&2
  exit 1
fi

VERSION="$1"
ARCHIVE_PATH="$2"

if [[ ! -f "$ARCHIVE_PATH" ]]; then
  echo "Error: Archive not found: $ARCHIVE_PATH" >&2
  exit 1
fi

if [[ -z "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  echo "Error: SPARKLE_PRIVATE_KEY environment variable is not set" >&2
  exit 1
fi

# --- Create temp directory (cleaned up on exit) ---

TMPDIR_APPCAST="$(mktemp -d)"
cleanup() {
  rm -rf "$TMPDIR_APPCAST"
}
trap cleanup EXIT

# --- Download and extract Sparkle tools ---

echo "Downloading Sparkle ${SPARKLE_VERSION} tools..."
SPARKLE_TARBALL="$TMPDIR_APPCAST/Sparkle.tar.xz"
curl -fsSL -o "$SPARKLE_TARBALL" "$SPARKLE_URL"

echo "Extracting Sparkle tools..."
SPARKLE_EXTRACT="$TMPDIR_APPCAST/sparkle"
mkdir -p "$SPARKLE_EXTRACT"
tar -xf "$SPARKLE_TARBALL" -C "$SPARKLE_EXTRACT"

GENERATE_APPCAST="$SPARKLE_EXTRACT/bin/generate_appcast"
SIGN_UPDATE="$SPARKLE_EXTRACT/bin/sign_update"

if [[ ! -x "$GENERATE_APPCAST" ]]; then
  echo "Error: generate_appcast binary not found at $GENERATE_APPCAST" >&2
  exit 1
fi

if [[ ! -x "$SIGN_UPDATE" ]]; then
  echo "Error: sign_update binary not found at $SIGN_UPDATE" >&2
  exit 1
fi

# --- Write private key to temp file ---

KEY_FILE="$TMPDIR_APPCAST/sparkle_private_key"
echo -n "$SPARKLE_PRIVATE_KEY" > "$KEY_FILE"
chmod 600 "$KEY_FILE"

# --- Prepare updates directory ---

UPDATES_DIR="$TMPDIR_APPCAST/updates"
mkdir -p "$UPDATES_DIR"
cp "$ARCHIVE_PATH" "$UPDATES_DIR/"

# If an existing appcast.xml is present, copy it so generate_appcast
# can merge the new entry with previous releases.
if [[ -f "./appcast.xml" ]]; then
  echo "Found existing appcast.xml — merging with new release."
  cp "./appcast.xml" "$UPDATES_DIR/appcast.xml"
fi

# --- Generate appcast.xml ---

echo "Generating appcast.xml..."
"$GENERATE_APPCAST" \
  --ed-key-file "$KEY_FILE" \
  --download-url-prefix "https://github.com/vaayne/mori/releases/download/v${VERSION}/" \
  "$UPDATES_DIR"

# --- Copy output ---

if [[ -f "$UPDATES_DIR/appcast.xml" ]]; then
  cp "$UPDATES_DIR/appcast.xml" ./appcast.xml
  echo "Generated appcast.xml successfully."
else
  echo "Error: appcast.xml was not generated" >&2
  exit 1
fi
