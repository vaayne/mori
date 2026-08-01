#!/usr/bin/env bash
# Machine-readable GhosttyKit contract helpers. The root lock is the authority.

_ghosttykit_contract_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GHOSTTYKIT_DEFAULT_LOCK="$(cd "$_ghosttykit_contract_dir/.." && pwd)/ghosttykit-lock.json"

_ghosttykit_fail() {
    echo "GhosttyKit contract failed: $*" >&2
    return 1
}

# Load a strictly validated lock without evaluating lock-controlled shell text.
ghosttykit_load_contract() {
    local lock_path="${1:-$GHOSTTYKIT_DEFAULT_LOCK}"
    [[ -f "$lock_path" ]] || { _ghosttykit_fail "missing lock file: $lock_path"; return 1; }

    local values
    values="$(python3 - "$lock_path" <<'PY'
import json
import re
import sys

class ContractError(Exception):
    pass

def reject_duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ContractError(f"duplicate key: {key}")
        result[key] = value
    return result

def expect_object(value, path, keys):
    if not isinstance(value, dict):
        raise ContractError(f"{path} must be an object")
    actual = set(value)
    expected = set(keys)
    if actual != expected:
        missing = ", ".join(sorted(expected - actual))
        unknown = ", ".join(sorted(actual - expected))
        parts = []
        if missing:
            parts.append(f"missing: {missing}")
        if unknown:
            parts.append(f"unknown: {unknown}")
        raise ContractError(f"{path} keys do not match schema ({'; '.join(parts)})")
    return value

def expect_string(value, path, pattern=None):
    if not isinstance(value, str) or not value:
        raise ContractError(f"{path} must be a non-empty string")
    if pattern and not re.fullmatch(pattern, value):
        raise ContractError(f"{path} has an invalid value")
    return value

def expect_positive_int(value, path):
    if isinstance(value, bool) or not isinstance(value, int) or value < 1:
        raise ContractError(f"{path} must be a positive integer")
    return value

def expect_digest(value, path):
    if value is None:
        return None
    return expect_string(value, path, r"[0-9a-f]{64}")

try:
    with open(sys.argv[1], encoding="utf-8") as stream:
        lock = json.load(stream, object_pairs_hook=reject_duplicates)

    expect_object(lock, "root", {"schemaVersion", "source", "build", "artifact"})
    if isinstance(lock["schemaVersion"], bool) or lock["schemaVersion"] != 1:
        raise ContractError("schemaVersion must be 1")

    source = expect_object(lock["source"], "source", {
        "repository", "commit", "upstreamBaseCommit",
    })
    repository = expect_string(source["repository"], "source.repository", r"https://[A-Za-z0-9.-]+/[A-Za-z0-9._/-]+\.git")
    source_commit = expect_string(source["commit"], "source.commit", r"[0-9a-f]{40}")
    base_commit = expect_string(source["upstreamBaseCommit"], "source.upstreamBaseCommit", r"[0-9a-f]{40}")

    build = expect_object(lock["build"], "build", {
        "revision", "ghosttyVersion", "zigVersion", "zigArchiveSha256", "optimize",
        "buildMode", "target", "minimumIOSMajor",
    })
    revision = expect_positive_int(build["revision"], "build.revision")
    version = expect_string(build["ghosttyVersion"], "build.ghosttyVersion", r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?")
    zig_version = expect_string(build["zigVersion"], "build.zigVersion", r"[0-9]+\.[0-9]+\.[0-9]+")
    zig_archive_sha256 = expect_string(build["zigArchiveSha256"], "build.zigArchiveSha256", r"[0-9a-f]{64}")
    optimize = expect_string(build["optimize"], "build.optimize", r"[A-Za-z][A-Za-z0-9_-]*")
    build_mode = expect_positive_int(build["buildMode"], "build.buildMode")
    target = expect_string(build["target"], "build.target", r"[a-z][a-z0-9_-]*")
    minimum_ios_major = expect_positive_int(build["minimumIOSMajor"], "build.minimumIOSMajor")

    artifact = expect_object(lock["artifact"], "artifact", {
        "repository", "tag", "name", "sha256", "frameworkTreeSha256",
    })
    artifact_repository = expect_string(artifact["repository"], "artifact.repository", r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")
    tag = expect_string(artifact["tag"], "artifact.tag", r"[A-Za-z0-9._-]+")
    name = expect_string(artifact["name"], "artifact.name", r"[A-Za-z0-9._-]+\.zip")
    archive_sha256 = expect_digest(artifact["sha256"], "artifact.sha256")
    framework_tree_sha256 = expect_digest(artifact["frameworkTreeSha256"], "artifact.frameworkTreeSha256")

    short_commit = source_commit[:8]
    expected_tag = f"ghosttykit-{short_commit}-r{revision}"
    expected_name = f"GhosttyKit-{short_commit}-r{revision}-universal.zip"
    if tag != expected_tag:
        raise ContractError("artifact.tag does not match source.commit and build.revision")
    if name != expected_name:
        raise ContractError("artifact.name does not match source.commit and build.revision")
    if target != "universal":
        raise ContractError("build.target must be universal for the durable artifact")
    if (archive_sha256 is None) != (framework_tree_sha256 is None):
        raise ContractError("artifact digests must both be null (candidate) or both be final")

    fields = [
        source_commit, base_commit, repository, version, str(revision), zig_version,
        zig_archive_sha256, optimize, str(build_mode), target, str(minimum_ios_major),
        artifact_repository, tag, name, archive_sha256 or "", framework_tree_sha256 or "",
    ]
    print("\t".join(fields))
except (OSError, json.JSONDecodeError, ContractError) as error:
    print(f"GhosttyKit lock validation failed: {error}", file=sys.stderr)
    sys.exit(1)
PY
)" || return 1

    local source_commit base_commit source_repository version revision zig_version zig_archive_sha256
    local optimize build_mode target minimum_ios_major artifact_repository tag name archive_sha256 framework_tree_sha256
    IFS=$'\t' read -r source_commit base_commit source_repository version revision zig_version zig_archive_sha256 optimize build_mode target minimum_ios_major artifact_repository tag name archive_sha256 framework_tree_sha256 <<<"$values"

    MORI_GHOSTTYKIT_SOURCE_COMMIT="$source_commit"
    MORI_GHOSTTYKIT_BASE_COMMIT="$base_commit"
    MORI_GHOSTTYKIT_SOURCE_REPOSITORY="$source_repository"
    MORI_GHOSTTYKIT_VERSION="$version"
    MORI_GHOSTTYKIT_BUILD_REVISION="$revision"
    MORI_GHOSTTYKIT_ZIG_VERSION="$zig_version"
    MORI_GHOSTTYKIT_ZIG_ARCHIVE_SHA256="$zig_archive_sha256"
    MORI_GHOSTTYKIT_OPTIMIZE="$optimize"
    MORI_GHOSTTYKIT_BUILD_MODE="$build_mode"
    MORI_GHOSTTYKIT_TARGET="$target"
    MORI_GHOSTTYKIT_MIN_IOS_MAJOR="$minimum_ios_major"
    MORI_GHOSTTYKIT_ARTIFACT_REPOSITORY="$artifact_repository"
    MORI_GHOSTTYKIT_ARTIFACT_TAG="$tag"
    MORI_GHOSTTYKIT_ARTIFACT_NAME="$name"
    MORI_GHOSTTYKIT_ARTIFACT_SHA256="$archive_sha256"
    MORI_GHOSTTYKIT_FRAMEWORK_TREE_SHA256="$framework_tree_sha256"

    if [[ -z "$MORI_GHOSTTYKIT_ARTIFACT_SHA256" ]]; then
        MORI_GHOSTTYKIT_ARTIFACT_STATE="candidate"
    else
        MORI_GHOSTTYKIT_ARTIFACT_STATE="published"
    fi
}

ghosttykit_validate_source_metadata() {
    local project_root="$1"
    local configured_url gitlink mode commit path
    configured_url="$(git -C "$project_root" config -f .gitmodules --get submodule.vendor/ghostty.url 2>/dev/null || true)"
    [[ "$configured_url" == "$MORI_GHOSTTYKIT_SOURCE_REPOSITORY" ]] || {
        _ghosttykit_fail "vendor/ghostty URL does not match the lock"
        return 1
    }

    gitlink="$(git -C "$project_root" ls-tree HEAD -- vendor/ghostty)"
    read -r mode _ commit path <<<"$gitlink"
    [[ "$mode" == "160000" && "$commit" == "$MORI_GHOSTTYKIT_SOURCE_COMMIT" && "$path" == "vendor/ghostty" ]] || {
        _ghosttykit_fail "vendor/ghostty gitlink does not match the lock"
        return 1
    }
    git -C "$project_root" diff --quiet --cached -- vendor/ghostty || {
        _ghosttykit_fail "vendor/ghostty gitlink has staged changes"
        return 1
    }
}

ghosttykit_validate_source() {
    local project_root="$1"
    local ghostty_dir="$project_root/vendor/ghostty"
    ghosttykit_validate_source_metadata "$project_root" || return 1
    [[ -f "$ghostty_dir/build.zig" ]] || {
        _ghosttykit_fail "vendor/ghostty is not initialized"
        return 1
    }
    [[ "$(git -C "$ghostty_dir" rev-parse HEAD)" == "$MORI_GHOSTTYKIT_SOURCE_COMMIT" ]] || {
        _ghosttykit_fail "checked-out vendor/ghostty commit does not match the lock"
        return 1
    }
    [[ -z "$(git -C "$ghostty_dir" status --porcelain --untracked-files=all)" ]] || {
        _ghosttykit_fail "vendor/ghostty has tracked or untracked modifications"
        return 1
    }
}

# Publisher-only history check. Ordinary shallow CI checkouts still prove the
# exact source gitlink; the publisher fetches full history before calling this.
ghosttykit_validate_source_ancestry() {
    local project_root="$1"
    local ghostty_dir="$project_root/vendor/ghostty"
    git -C "$ghostty_dir" merge-base --is-ancestor "$MORI_GHOSTTYKIT_BASE_COMMIT" "$MORI_GHOSTTYKIT_SOURCE_COMMIT" || {
        _ghosttykit_fail "locked upstream base is not an ancestor of the locked source"
        return 1
    }
}

ghosttykit_validate_zig() {
    command -v zig >/dev/null 2>&1 || {
        _ghosttykit_fail "zig is not installed"
        return 1
    }
    [[ "$(zig version)" == "$MORI_GHOSTTYKIT_ZIG_VERSION" ]] || {
        _ghosttykit_fail "installed zig does not match the locked version"
        return 1
    }
}

# A tree digest is content + relative path sensitive and rejects symlinks/special files.
ghosttykit_framework_tree_sha256() {
    local root="$1"
    [[ -d "$root" ]] || {
        _ghosttykit_fail "missing framework tree: $root"
        return 1
    }
    python3 - "$root" <<'PY'
import hashlib
import os
import stat
import sys

root = os.path.abspath(sys.argv[1])
digest = hashlib.sha256()
for current, directories, files in os.walk(root, topdown=True, followlinks=False):
    directories.sort()
    files.sort()
    for name in directories + files:
        path = os.path.join(current, name)
        mode = os.lstat(path).st_mode
        if stat.S_ISLNK(mode) or not (stat.S_ISDIR(mode) or stat.S_ISREG(mode)):
            raise SystemExit(f"unsafe framework tree entry: {os.path.relpath(path, root)}")
    for name in files:
        path = os.path.join(current, name)
        relative = os.path.relpath(path, root).encode("utf-8")
        content = hashlib.sha256()
        with open(path, "rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                content.update(chunk)
        digest.update(b"file\0")
        digest.update(len(relative).to_bytes(8, "big"))
        digest.update(relative)
        digest.update(content.digest())
print(digest.hexdigest())
PY
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    lock_path="$GHOSTTYKIT_DEFAULT_LOCK"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --lock)
                [[ $# -ge 2 ]] || { echo "Usage: $0 [--lock PATH]" >&2; exit 2; }
                lock_path="$2"
                shift
                ;;
            *)
                echo "Usage: $0 [--lock PATH]" >&2
                exit 2
                ;;
        esac
        shift
    done
    ghosttykit_load_contract "$lock_path" || exit 1
    printf 'GhosttyKit lock is a valid %s contract.\n' "$MORI_GHOSTTYKIT_ARTIFACT_STATE"
fi
