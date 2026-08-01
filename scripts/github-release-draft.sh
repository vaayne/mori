#!/usr/bin/env bash
# Create, verify, and publish GitHub Releases without ever uploading after publish.
set -Eeuo pipefail

usage() {
    cat >&2 <<'EOF'
Usage:
  github-release-draft.sh --create-draft --repo OWNER/REPO --tag TAG --target SHA --title TITLE
      [--generate-notes] [--prerelease] [--make-latest true|false] [--require-immutable]
      [--defer-asset-verification] [--download-assets] --asset PATH [--asset PATH ...]
  github-release-draft.sh --verify-draft-assets --repo OWNER/REPO --release-id ID
      [--download-assets] --asset PATH [--asset PATH ...]
  github-release-draft.sh --publish-draft --repo OWNER/REPO --release-id ID [--require-immutable]
  github-release-draft.sh --cleanup-draft --repo OWNER/REPO --release-id ID
  github-release-draft.sh --preflight --repo OWNER/REPO --tag TAG --target SHA --title TITLE
      --asset PATH --asset PATH [...]
EOF
}

incomplete_draft=false

cleanup_incomplete_draft() {
    set +e
    if [[ "$incomplete_draft" == true && "$release_id" =~ ^[0-9]+$ ]] && release_is_draft; then
        gh api --method DELETE "repos/$repo/releases/$release_id" --silent
        echo "Deleted incomplete draft release $release_id." >&2
    fi
}

fail() {
    cleanup_incomplete_draft
    echo "GitHub release draft failed: $*" >&2
    exit 1
}

mode=""
repo="${GITHUB_REPOSITORY:-}"
tag=""
target=""
title=""
release_id=""
generate_notes=false
prerelease=false
make_latest=false
require_immutable=false
defer_asset_verification=false
download_assets=false
assets=()
trap 'status=$?; cleanup_incomplete_draft; exit "$status"' ERR

while [[ $# -gt 0 ]]; do
    case "$1" in
        --create-draft|--verify-draft-assets|--publish-draft|--cleanup-draft|--preflight)
            [[ -z "$mode" ]] || fail "choose exactly one mode"
            mode="${1#--}"
            ;;
        --repo|--tag|--target|--title|--release-id|--make-latest)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            case "$1" in
                --repo) repo="$2" ;;
                --tag) tag="$2" ;;
                --target) target="$2" ;;
                --title) title="$2" ;;
                --release-id) release_id="$2" ;;
                --make-latest) make_latest="$2" ;;
            esac
            shift
            ;;
        --asset)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            assets+=("$2")
            shift
            ;;
        --generate-notes) generate_notes=true ;;
        --prerelease) prerelease=true ;;
        --require-immutable) require_immutable=true ;;
        --defer-asset-verification) defer_asset_verification=true ;;
        --download-assets) download_assets=true ;;
        *) usage; exit 2 ;;
    esac
    shift
done

[[ -n "$mode" && "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { usage; exit 2; }
[[ "$make_latest" == true || "$make_latest" == false ]] || fail "--make-latest must be true or false"
command -v gh >/dev/null 2>&1 || fail "gh is required"

require_assets() {
    [[ "${#assets[@]}" -gt 0 ]] || fail "at least one --asset is required"
    local asset name
    for asset in "${assets[@]}"; do
        [[ -f "$asset" ]] || fail "missing asset: $asset"
        name="$(basename "$asset")"
        [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail "asset name is not API-safe: $name"
    done
}

api_404_is_absent() {
    local endpoint="$1" response status
    set +e
    response="$(gh api --include "$endpoint" 2>&1)"
    status=$?
    set -e
    if [[ "$status" -eq 0 ]]; then
        return 1
    fi
    [[ "$response" == *"404"* ]] || fail "could not establish that $endpoint is absent: $response"
    return 0
}

immutable_releases_enabled() {
    [[ "$(gh api "repos/$repo/immutable-releases" --jq '.enabled')" == true ]] || \
        fail "repository immutable releases must be enabled before publishing"
}

latest_tag() {
    local response status
    set +e
    response="$(gh api "repos/$repo/releases/latest" --jq '.tag_name' 2>&1)"
    status=$?
    set -e
    if [[ "$status" -eq 0 ]]; then
        printf '%s\n' "$response"
    elif [[ "$response" == *"404"* ]]; then
        printf '%s\n' "__none__"
    else
        fail "could not resolve Latest: $response"
    fi
}

release_is_draft() {
    [[ "$(gh api "repos/$repo/releases/$release_id" --jq '.draft')" == true ]]
}

cleanup_draft() {
    if [[ -n "$release_id" ]] && release_is_draft; then
        gh api --method DELETE "repos/$repo/releases/$release_id" --silent
        echo "Deleted unpublished draft release $release_id."
    fi
}

verify_assets() {
    local release_json records name asset_id digest local_path local_digest downloaded
    release_json="$(gh api "repos/$repo/releases/$release_id")"
    records="$(python3 - "$release_json" "${assets[@]}" <<'PY'
import json
import os
import sys

release = json.loads(sys.argv[1])
by_name = {asset["name"]: asset for asset in release.get("assets", [])}
for path in sys.argv[2:]:
    name = os.path.basename(path)
    asset = by_name.get(name)
    if not asset:
        raise SystemExit(f"missing uploaded asset: {name}")
    digest = asset.get("digest")
    if not isinstance(digest, str) or not digest.startswith("sha256:") or len(digest) != 71:
        raise SystemExit(f"server digest is unavailable for {name}")
    print(f"{name}\t{asset['id']}\t{digest[7:]}")
PY
)" || return 1

    while IFS=$'\t' read -r name asset_id digest; do
        local_path=""
        for asset in "${assets[@]}"; do
            [[ "$(basename "$asset")" == "$name" ]] && local_path="$asset" && break
        done
        [[ -n "$local_path" ]] || fail "lost local asset mapping for $name"
        local_digest="$(shasum -a 256 "$local_path" | awk '{print $1}')"
        [[ "$local_digest" == "$digest" ]] || fail "server digest differs for $name"
        if [[ "$download_assets" == true ]]; then
            downloaded="$(mktemp "${TMPDIR:-/tmp}/mori-release-asset.XXXXXX")"
            gh api -H 'Accept: application/octet-stream' "repos/$repo/releases/assets/$asset_id" >"$downloaded"
            [[ "$(shasum -a 256 "$downloaded" | awk '{print $1}')" == "$local_digest" ]] || \
                fail "downloaded asset differs for $name"
            rm -f "$downloaded"
        fi
    done <<<"$records"
}

wait_for_verified_assets() {
    local attempt
    for attempt in $(seq 1 15); do
        if verify_assets; then
            return 0
        fi
        sleep 2
    done
    fail "uploaded assets did not acquire matching server digests"
}

create_draft() {
    require_assets
    [[ -n "$tag" && -n "$target" && -n "$title" ]] || fail "--tag, --target, and --title are required"
    [[ "$tag" =~ ^[A-Za-z0-9._-]+$ ]] || fail "tag is not API-safe"
    if [[ "$require_immutable" == true ]]; then
        immutable_releases_enabled
    fi
    api_404_is_absent "repos/$repo/releases/tags/$tag" || fail "refusing to overwrite existing release tag: $tag"

    local body response
    body="$(mktemp "${TMPDIR:-/tmp}/mori-release-create.XXXXXX")"
    trap 'rm -f "$body"' RETURN
    python3 - "$body" "$tag" "$target" "$title" "$generate_notes" "$prerelease" "$make_latest" <<'PY'
import json
import sys
path, tag, target, title, notes, prerelease, latest = sys.argv[1:]
with open(path, "w", encoding="utf-8") as stream:
    json.dump({
        "tag_name": tag,
        "target_commitish": target,
        "name": title,
        "draft": True,
        "prerelease": prerelease == "true",
        "generate_release_notes": notes == "true",
        "make_latest": latest,
    }, stream)
PY
    response="$(gh api --method POST "repos/$repo/releases" --input "$body")"
    rm -f "$body"
    trap - RETURN
    release_id="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<<"$response")" || fail "draft creation returned no release id"
    [[ "$release_id" =~ ^[0-9]+$ ]] || fail "draft creation returned invalid release id"
    incomplete_draft=true

    local asset name
    for asset in "${assets[@]}"; do
        name="$(basename "$asset")"
        gh api --method POST "https://uploads.github.com/repos/$repo/releases/$release_id/assets?name=$name" \
            -H 'Content-Type: application/octet-stream' --input "$asset" --silent
    done
    if [[ "$defer_asset_verification" != true ]]; then
        wait_for_verified_assets
    fi
    incomplete_draft=false
    printf 'release_id=%s\n' "$release_id"
}

publish_draft() {
    [[ "$release_id" =~ ^[0-9]+$ ]] || fail "--release-id is required"
    if [[ "$require_immutable" == true ]]; then
        immutable_releases_enabled
    fi
    release_is_draft || fail "refusing to publish a release that is not a draft"
    local body response immutable
    body="$(mktemp "${TMPDIR:-/tmp}/mori-release-publish.XXXXXX")"
    printf '{"draft":false}\n' >"$body"
    response="$(gh api --method PATCH "repos/$repo/releases/$release_id" --input "$body")"
    rm -f "$body"
    [[ "$(python3 -c 'import json,sys; print(str(json.load(sys.stdin).get("draft")).lower())' <<<"$response")" == false ]] || \
        fail "GitHub did not publish the release"
    immutable="$(python3 -c 'import json,sys; print(str(json.load(sys.stdin).get("immutable")).lower())' <<<"$response")"
    [[ "$immutable" == true ]] || fail "published release is not immutable"
    echo "Published immutable release $release_id."
}

case "$mode" in
    create-draft)
        create_draft
        ;;
    verify-draft-assets)
        [[ "$release_id" =~ ^[0-9]+$ ]] || fail "--release-id is required"
        release_is_draft || fail "refusing to verify a release that is not a draft"
        require_assets
        wait_for_verified_assets
        ;;
    publish-draft)
        publish_draft
        ;;
    cleanup-draft)
        [[ "$release_id" =~ ^[0-9]+$ ]] || fail "--release-id is required"
        cleanup_draft
        ;;
    preflight)
        latest_before="$(latest_tag)"
        echo "Latest before draft: $latest_before"
        create_draft
        incomplete_draft=true
        latest_after="$(latest_tag)"
        [[ "$latest_before" == "$latest_after" ]] || fail "Latest changed while only a draft existed"
        cleanup_draft
        incomplete_draft=false
        echo "Latest after draft cleanup: $latest_after"
        echo "Draft preflight preserved Latest: $latest_before"
        ;;
esac
