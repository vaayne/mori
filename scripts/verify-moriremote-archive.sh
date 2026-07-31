#!/usr/bin/env bash
# Inspect an unsigned or signed MoriRemote archive without exporting/uploading it.
set -euo pipefail

archive="${1:?Usage: $0 path/to/MoriRemote.xcarchive [marketing-version] [build-number]}"
expected_version="${2:-0.3.5}"
expected_build_number="${3:-}"
app="$archive/Products/Applications/MoriRemote.app"
plist="$app/Info.plist"

fail() { echo "MoriRemote archive verification failed: $*" >&2; exit 1; }
[[ -d "$app" ]] || fail "missing application bundle"
[[ -f "$plist" ]] || fail "missing Info.plist"
[[ "$(plutil -extract CFBundleIdentifier raw "$plist")" == "com.vaayne.mori-remote" ]] || fail "unexpected bundle identifier"
[[ "$(plutil -extract CFBundleShortVersionString raw "$plist")" == "$expected_version" ]] || fail "unexpected marketing version"
if [[ -n "$expected_build_number" ]]; then
    [[ "$(plutil -extract CFBundleVersion raw "$plist")" == "$expected_build_number" ]] || fail "unexpected build number"
fi
[[ -f "$app/en.lproj/Localizable.strings" ]] || fail "missing English localization"
[[ -f "$app/zh-Hans.lproj/Localizable.strings" ]] || fail "missing Simplified Chinese localization"
[[ -f "$app/PrivacyInfo.xcprivacy" ]] || fail "missing privacy manifest"
[[ -f "$app/THIRD_PARTY_NOTICES.md" ]] || fail "missing bundled third-party notices"
[[ -f "$app/THIRD_PARTY_LICENSES/Apache-2.0.txt" ]] || fail "missing bundled Apache notice"

legacy_payload="$(find "$app" \( -iname '*swiftterm*' -o -iname '*moritmux*' -o -iname '*moriterminal*' -o -iname '*moricore*' -o -iname '*morissh*' \) -print -quit)"
[[ -z "$legacy_payload" ]] || fail "legacy terminal payload found: $legacy_payload"
if otool -L "$app/MoriRemote" 2>/dev/null | grep -qi 'swiftterm'; then
    fail "MoriRemote links SwiftTerm"
fi

printf 'Verified MoriRemote archive: bundle ID, version %s%s, localizations, privacy manifest, notices, and no legacy terminal payload.\n' "$expected_version" "${expected_build_number:+ build $expected_build_number}"
