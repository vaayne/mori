#!/usr/bin/env bash
# Offline adversarial tests for the root GhosttyKit contract and its source/tree checks.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../ghosttykit-contract.sh
source "$repo_root/scripts/ghosttykit-contract.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/mori-ghosttykit-contract.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

die() {
    echo "GhosttyKit contract test failed: $*" >&2
    exit 1
}

expect_reject() {
    local description="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        die "accepted $description"
    fi
}

write_lock() {
    local path="$1" source_commit="$2" base_commit="$3" revision="$4"
    python3 - "$path" "$source_commit" "$base_commit" "$revision" <<'PY'
import json
import sys

path, source, base, revision = sys.argv[1:]
revision = int(revision)
short = source[:8]
lock = {
    "schemaVersion": 1,
    "source": {
        "repository": "https://example.test/remux-ghostty.git",
        "commit": source,
        "upstreamBaseCommit": base,
    },
    "build": {
        "revision": revision,
        "ghosttyVersion": "9.9.9-test",
        "zigVersion": "9.9.9",
        "zigArchiveSha256": "a" * 64,
        "optimize": "Test",
        "buildMode": 2,
        "target": "universal",
        "minimumIOSMajor": 17,
    },
    "artifact": {
        "repository": "example/mori",
        "tag": f"ghosttykit-{short}-r{revision}",
        "name": f"GhosttyKit-{short}-r{revision}-universal.zip",
        "sha256": None,
        "frameworkTreeSha256": None,
    },
}
with open(path, "w", encoding="utf-8") as stream:
    json.dump(lock, stream)
PY
}

# The checked-in lock deliberately has no digest until the first trusted publish.
ghosttykit_load_contract "$repo_root/ghosttykit-lock.json"
[[ "$MORI_GHOSTTYKIT_ARTIFACT_STATE" == "candidate" ]] || die "current lock is not a valid candidate"

invalid_json="$tmp/invalid.json"
printf '{not json}\n' >"$invalid_json"
expect_reject "malformed JSON" bash "$repo_root/scripts/ghosttykit-contract.sh" --lock "$invalid_json"

missing_field="$tmp/missing-field.json"
printf '{"schemaVersion":1}\n' >"$missing_field"
expect_reject "missing schema field" bash "$repo_root/scripts/ghosttykit-contract.sh" --lock "$missing_field"

unknown_field="$tmp/unknown-field.json"
python3 - "$repo_root/ghosttykit-lock.json" "$unknown_field" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    value = json.load(stream)
value["unexpected"] = True
with open(sys.argv[2], "w", encoding="utf-8") as stream:
    json.dump(value, stream)
PY
expect_reject "unknown schema field" bash "$repo_root/scripts/ghosttykit-contract.sh" --lock "$unknown_field"

duplicate_key="$tmp/duplicate-key.json"
printf '{"schemaVersion":1,"schemaVersion":1,"source":{},"build":{},"artifact":{}}\n' >"$duplicate_key"
expect_reject "duplicate JSON key" bash "$repo_root/scripts/ghosttykit-contract.sh" --lock "$duplicate_key"

published_lock="$tmp/published.json"
python3 - "$repo_root/ghosttykit-lock.json" "$published_lock" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    value = json.load(stream)
value["artifact"]["sha256"] = "a" * 64
value["artifact"]["frameworkTreeSha256"] = "b" * 64
with open(sys.argv[2], "w", encoding="utf-8") as stream:
    json.dump(value, stream)
PY
ghosttykit_load_contract "$published_lock"
[[ "$MORI_GHOSTTYKIT_ARTIFACT_STATE" == "published" ]] || die "valid final digests were not accepted"

partial_digest="$tmp/partial-digest.json"
python3 - "$published_lock" "$partial_digest" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    value = json.load(stream)
value["artifact"]["frameworkTreeSha256"] = None
with open(sys.argv[2], "w", encoding="utf-8") as stream:
    json.dump(value, stream)
PY
expect_reject "partial artifact digest state" bash "$repo_root/scripts/ghosttykit-contract.sh" --lock "$partial_digest"

child="$tmp/child"
super="$tmp/super"
git init -q "$child"
git -C "$child" config user.email test@example.test
git -C "$child" config user.name contract-test
printf 'base\n' >"$child/build.zig"
git -C "$child" add build.zig
git -C "$child" commit -qm base
base_commit="$(git -C "$child" rev-parse HEAD)"
printf 'source\n' >>"$child/build.zig"
git -C "$child" commit -qam source
source_commit="$(git -C "$child" rev-parse HEAD)"
git -C "$child" remote add origin https://example.test/remux-ghostty.git

git init -q "$super"
git -C "$super" config user.email test@example.test
git -C "$super" config user.name contract-test
mkdir -p "$super/vendor"
git clone -q "$child" "$super/vendor/ghostty"
cat >"$super/.gitmodules" <<'EOF'
[submodule "vendor/ghostty"]
	path = vendor/ghostty
	url = https://example.test/remux-ghostty.git
EOF
git -C "$super" add .gitmodules
git -C "$super" update-index --add --cacheinfo "160000,$source_commit,vendor/ghostty"
git -C "$super" commit -qm contract

valid_lock="$tmp/valid.json"
write_lock "$valid_lock" "$source_commit" "$base_commit" 7
ghosttykit_load_contract "$valid_lock"
ghosttykit_validate_source "$super"

sed -i '' 's#https://example.test/remux-ghostty.git#https://example.test/wrong.git#' "$super/.gitmodules"
expect_reject "submodule URL mismatch" ghosttykit_validate_source "$super"
sed -i '' 's#https://example.test/wrong.git#https://example.test/remux-ghostty.git#' "$super/.gitmodules"
git -C "$super/vendor/ghostty" checkout -q "$base_commit"
expect_reject "checked-out submodule mismatch" ghosttykit_validate_source "$super"
git -C "$super/vendor/ghostty" checkout -q "$source_commit"

ghosttykit_load_contract "$valid_lock"
ghosttykit_validate_source "$super"

git -C "$super" update-index --cacheinfo "160000,$base_commit,vendor/ghostty"
expect_reject "staged submodule gitlink mismatch" ghosttykit_validate_source "$super"
git -C "$super" reset -q -- vendor/ghostty

ghosttykit_load_contract "$valid_lock"
ghosttykit_validate_source "$super"

source_mismatch_lock="$tmp/source-mismatch.json"
write_lock "$source_mismatch_lock" "$base_commit" "$base_commit" 7
ghosttykit_load_contract "$source_mismatch_lock"
expect_reject "submodule gitlink mismatch" ghosttykit_validate_source "$super"

revision_mismatch_lock="$tmp/revision-mismatch.json"
write_lock "$revision_mismatch_lock" "$source_commit" "$base_commit" 8
python3 - "$revision_mismatch_lock" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    value = json.load(stream)
value["artifact"]["tag"] = value["artifact"]["tag"].replace("-r8", "-r7")
with open(sys.argv[1], "w", encoding="utf-8") as stream:
    json.dump(value, stream)
PY
expect_reject "revision-derived tag mismatch" bash "$repo_root/scripts/ghosttykit-contract.sh" --lock "$revision_mismatch_lock"

ghosttykit_load_contract "$valid_lock"
mkdir -p "$tmp/bin"
printf '#!/usr/bin/env bash\nprintf "0.0.0\\n"\n' >"$tmp/bin/zig"
chmod +x "$tmp/bin/zig"
expect_reject "toolchain version mismatch" env PATH="$tmp/bin:$PATH" bash -c 'source "$1"; ghosttykit_load_contract "$2"; ghosttykit_validate_zig' _ "$repo_root/scripts/ghosttykit-contract.sh" "$valid_lock"

framework="$tmp/GhosttyKit.xcframework"
mkdir -p "$framework/Headers"
printf 'original\n' >"$framework/Info.plist"
printf 'header\n' >"$framework/Headers/ghostty.h"
tree_sha256="$(ghosttykit_framework_tree_sha256 "$framework")"
printf 'mutated\n' >>"$framework/Info.plist"
[[ "$(ghosttykit_framework_tree_sha256 "$framework")" != "$tree_sha256" ]] || die "tree mutation did not change digest"
ln -s Info.plist "$framework/unsafe-link"
expect_reject "symlinked framework entry" ghosttykit_framework_tree_sha256 "$framework"

workflow="$repo_root/.github/workflows/build-ghosttykit.yml"
installer="$repo_root/scripts/install-verified-zig.sh"
grep -Fq "hashFiles('ghosttykit-lock.json')" "$workflow" || die "workflow cache is not keyed by the complete lock"
grep -Fq 'scripts/install-verified-zig.sh' "$workflow" || die "workflow does not use the shared verified Zig installer"
grep -Fq 'MORI_GHOSTTYKIT_ZIG_ARCHIVE_SHA256' "$installer" || die "shared Zig installer does not verify the locked archive digest"

echo "✅ GhosttyKit contract accepts the candidate and rejects malformed, mismatched, and mutated fixtures"
