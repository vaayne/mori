#!/usr/bin/env bash
# Package one verified universal GhosttyKit candidate. ZIP bytes are not claimed reproducible.
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=ghosttykit-contract.sh
source "$project_root/scripts/ghosttykit-contract.sh"
ghosttykit_load_contract "$project_root/ghosttykit-lock.json"
export MORI_GHOSTTYKIT_SOURCE_COMMIT MORI_GHOSTTYKIT_BASE_COMMIT MORI_GHOSTTYKIT_SOURCE_REPOSITORY
export MORI_GHOSTTYKIT_VERSION MORI_GHOSTTYKIT_BUILD_REVISION MORI_GHOSTTYKIT_ZIG_VERSION MORI_GHOSTTYKIT_ZIG_ARCHIVE_SHA256
export MORI_GHOSTTYKIT_OPTIMIZE MORI_GHOSTTYKIT_BUILD_MODE MORI_GHOSTTYKIT_TARGET MORI_GHOSTTYKIT_MIN_IOS_MAJOR
export MORI_GHOSTTYKIT_ARTIFACT_REPOSITORY MORI_GHOSTTYKIT_ARTIFACT_TAG MORI_GHOSTTYKIT_ARTIFACT_NAME

output_dir="$project_root/.derived-data/ghosttykit-package"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            [[ $# -ge 2 ]] || { echo "Usage: $0 [--output DIRECTORY]" >&2; exit 2; }
            output_dir="$2"
            shift
            ;;
        *)
            echo "Usage: $0 [--output DIRECTORY]" >&2
            exit 2
            ;;
    esac
    shift
done

mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd -P)"
xcframework="$project_root/Frameworks/GhosttyKit.xcframework"
resources="$project_root/Frameworks/ghostty-resources"
source_license="$project_root/vendor/ghostty/LICENSE"
archive_path="$output_dir/$MORI_GHOSTTYKIT_ARTIFACT_NAME"
manifest_path="$output_dir/${MORI_GHOSTTYKIT_ARTIFACT_NAME%.zip}.manifest.json"

fail() {
    echo "GhosttyKit packaging failed: $*" >&2
    exit 1
}

[[ "$MORI_GHOSTTYKIT_ARTIFACT_STATE" == "candidate" ]] || fail "only a candidate lock may create a new package revision"
[[ ! -e "$archive_path" && ! -e "$manifest_path" ]] || fail "refusing to overwrite an existing package output"
[[ -d "$xcframework" ]] || fail "missing GhosttyKit.xcframework"
[[ -d "$resources" ]] || fail "missing ghostty-resources"
[[ -f "$source_license" ]] || fail "missing Ghostty/remux license"
command -v zip >/dev/null 2>&1 || fail "zip is required to create the archive"

ghosttykit_validate_source "$project_root" || fail "source checkout does not match the lock"
ghosttykit_validate_source_ancestry "$project_root" || fail "source history does not match the locked upstream base"
ghosttykit_validate_zig || fail "installed Zig does not match the lock"
MORI_GHOSTTYKIT_XCFRAMEWORK="$xcframework" bash "$project_root/scripts/verify-ghosttykit.sh"

framework_tree_sha256="$(ghosttykit_framework_tree_sha256 "$xcframework")"

staging="$(mktemp -d "${TMPDIR:-/tmp}/mori-ghosttykit-package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
payload="$staging/payload"
mkdir -p "$payload/LICENSES" "$output_dir"
cp -R "$xcframework" "$payload/GhosttyKit.xcframework"
cp -R "$resources" "$payload/ghostty-resources"
# remux-ghostty carries Ghostty's MIT license; retain explicit names for both redistributions.
cp "$source_license" "$payload/LICENSES/Ghostty-MIT.txt"
cp "$source_license" "$payload/LICENSES/remux-ghostty-MIT.txt"

xcode_version="$(xcodebuild -version 2>/dev/null | tr '\n' ';' | sed 's/;*$//')"
python3 - "$payload/ghosttykit-provenance.json" "$framework_tree_sha256" "$xcode_version" <<'PY'
import json
import os
import sys

path, framework_tree_sha256, xcode_version = sys.argv[1:]
provenance = {
    "schemaVersion": 1,
    "source": {
        "repository": os.environ["MORI_GHOSTTYKIT_SOURCE_REPOSITORY"],
        "commit": os.environ["MORI_GHOSTTYKIT_SOURCE_COMMIT"],
        "upstreamBaseCommit": os.environ["MORI_GHOSTTYKIT_BASE_COMMIT"],
    },
    "build": {
        "revision": int(os.environ["MORI_GHOSTTYKIT_BUILD_REVISION"]),
        "ghosttyVersion": os.environ["MORI_GHOSTTYKIT_VERSION"],
        "zigVersion": os.environ["MORI_GHOSTTYKIT_ZIG_VERSION"],
        "zigArchiveSha256": os.environ["MORI_GHOSTTYKIT_ZIG_ARCHIVE_SHA256"],
        "optimize": os.environ["MORI_GHOSTTYKIT_OPTIMIZE"],
        "buildMode": int(os.environ["MORI_GHOSTTYKIT_BUILD_MODE"]),
        "target": os.environ["MORI_GHOSTTYKIT_TARGET"],
        "minimumIOSMajor": int(os.environ["MORI_GHOSTTYKIT_MIN_IOS_MAJOR"]),
    },
    "artifact": {
        "repository": os.environ["MORI_GHOSTTYKIT_ARTIFACT_REPOSITORY"],
        "tag": os.environ["MORI_GHOSTTYKIT_ARTIFACT_TAG"],
        "name": os.environ["MORI_GHOSTTYKIT_ARTIFACT_NAME"],
        "frameworkTreeSha256": framework_tree_sha256,
    },
    "observedToolchain": {"xcodeVersion": xcode_version},
}
with open(path, "w", encoding="utf-8") as stream:
    json.dump(provenance, stream, indent=2, sort_keys=True)
    stream.write("\n")
PY

(
    cd "$payload"
    zip -qry "$archive_path" GhosttyKit.xcframework ghostty-resources ghosttykit-provenance.json LICENSES
)
archive_sha256="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
python3 - "$manifest_path" "$archive_sha256" "$framework_tree_sha256" <<'PY'
import json
import os
import sys

path, archive_sha256, framework_tree_sha256 = sys.argv[1:]
manifest = {
    "schemaVersion": 1,
    "artifact": {
        "repository": os.environ["MORI_GHOSTTYKIT_ARTIFACT_REPOSITORY"],
        "tag": os.environ["MORI_GHOSTTYKIT_ARTIFACT_TAG"],
        "name": os.environ["MORI_GHOSTTYKIT_ARTIFACT_NAME"],
        "sha256": archive_sha256,
        "frameworkTreeSha256": framework_tree_sha256,
    },
}
with open(path, "w", encoding="utf-8") as stream:
    json.dump(manifest, stream, indent=2, sort_keys=True)
    stream.write("\n")
PY

printf 'Packaged GhosttyKit candidate (ZIP bytes are not claimed reproducible):\n'
printf '  archive: %s\n  sha256: %s\n  framework tree: %s\n  manifest: %s\n' \
    "$archive_path" "$archive_sha256" "$framework_tree_sha256" "$manifest_path"
