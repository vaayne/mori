#!/usr/bin/env bash
# Atomically reserve and safely clean a lightweight GitHub release tag.
set -euo pipefail

usage() {
    echo "Usage: $0 (--reserve|--verify|--cleanup) --repo OWNER/REPO --tag TAG --sha COMMIT" >&2
}

mode=""
repo="${GITHUB_REPOSITORY:-}"
tag=""
sha=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --reserve|--verify|--cleanup)
            [[ -z "$mode" ]] || { usage; exit 2; }
            mode="${1#--}"
            ;;
        --repo|--tag|--sha)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            case "$1" in
                --repo) repo="$2" ;;
                --tag) tag="$2" ;;
                --sha) sha="$2" ;;
            esac
            shift
            ;;
        *) usage; exit 2 ;;
    esac
    shift
done

[[ -n "$mode" && "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { usage; exit 2; }
[[ "$tag" =~ ^[A-Za-z0-9._-]+$ && "$sha" =~ ^[0-9a-f]{40}$ ]] || { usage; exit 2; }
command -v gh >/dev/null 2>&1 || { echo "gh is required" >&2; exit 1; }

read_ref() {
    gh api "repos/$repo/git/ref/tags/$tag" --jq '[.object.type,.object.sha] | @tsv'
}

verify_ref() {
    local record type actual
    record="$(read_ref)"
    IFS=$'\t' read -r type actual <<<"$record"
    [[ "$type" == "commit" && "$actual" == "$sha" ]] || {
        echo "Tag $tag does not resolve directly to locked commit $sha." >&2
        return 1
    }
}

case "$mode" in
    reserve)
        # A successful POST is the ownership boundary. Verification is a
        # separate workflow step so cleanup still knows it owns the tag when a
        # subsequent GET fails transiently.
        gh api --method POST "repos/$repo/git/refs" \
            -f "ref=refs/tags/$tag" -f "sha=$sha" --silent
        echo "Reserved refs/tags/$tag at $sha."
        ;;
    verify)
        verify_ref
        ;;
    cleanup)
        # Once any release exists for the tag, immutable-release ownership wins.
        # Continue only after GitHub explicitly proves absence with HTTP 404;
        # transient API/auth failures must preserve the tag.
        set +e
        release_response="$(gh api --include "repos/$repo/releases/tags/$tag" 2>&1)"
        release_status=$?
        set -e
        if [[ "$release_status" -eq 0 ]]; then
            echo "Refusing to delete tag $tag because a release exists." >&2
            exit 1
        fi
        if [[ "$release_response" != *"404"* ]]; then
            echo "Refusing to delete tag $tag because release absence was not established: $release_response" >&2
            exit 1
        fi
        if ! verify_ref 2>/dev/null; then
            echo "Refusing to delete tag $tag because it is absent, moved, or annotated." >&2
            exit 1
        fi
        gh api --method DELETE "repos/$repo/git/refs/tags/$tag" --silent
        echo "Deleted unpublished reserved tag $tag."
        ;;
esac
