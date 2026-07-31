#!/usr/bin/env bash
# Keep archive contract checks independent from signing or App Store upload.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
verifier="$repo_root/scripts/verify-moriremote-archive.sh"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/mori-archive-verifier.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
app="$work_dir/MoriRemote.xcarchive/Products/Applications/MoriRemote.app"
mkdir -p "$app/en.lproj" "$app/zh-Hans.lproj" "$app/THIRD_PARTY_LICENSES"
touch "$app/en.lproj/Localizable.strings" "$app/zh-Hans.lproj/Localizable.strings"
touch "$app/PrivacyInfo.xcprivacy" "$app/THIRD_PARTY_NOTICES.md" "$app/THIRD_PARTY_LICENSES/Apache-2.0.txt" "$app/MoriRemote"
cat >"$app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.vaayne.mori-remote</string>
  <key>CFBundleShortVersionString</key><string>0.3.5</string>
  <key>CFBundleVersion</key><string>42</string>
</dict></plist>
PLIST

"$verifier" "$work_dir/MoriRemote.xcarchive" 0.3.5 42
if "$verifier" "$work_dir/MoriRemote.xcarchive" 0.3.5 43; then
    echo "Archive verifier accepted a mismatched build number." >&2
    exit 1
fi

for legacy_name in SwiftTerm MoriTmux MoriTerminal MoriCore MoriSSH; do
    touch "$app/$legacy_name"
    if "$verifier" "$work_dir/MoriRemote.xcarchive" 0.3.5 42; then
        echo "Archive verifier accepted legacy payload $legacy_name." >&2
        exit 1
    fi
    rm "$app/$legacy_name"
done

echo "✅ MoriRemote archive verifier enforces build number and legacy payload contract"
