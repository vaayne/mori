#!/usr/bin/env bash
# Offline release-draft protocol and workflow structure tests.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/mori-release-workflows.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

fail() {
    echo "Release workflow test failed: $*" >&2
    exit 1
}

expect_reject() {
    local description="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        fail "accepted $description"
    fi
}

assert_contains() {
    local path="$1" needle="$2"
    grep -Fq -- "$needle" "$path" || fail "$path is missing $needle"
}

assert_not_contains() {
    local path="$1" needle="$2"
    if grep -Fq -- "$needle" "$path"; then
        fail "$path unexpectedly contains $needle"
    fi
}

assert_order() {
    local path="$1" first="$2" second="$3" first_line second_line
    first_line="$(grep -nF -- "$first" "$path" | head -1 | cut -d: -f1)"
    second_line="$(grep -nF -- "$second" "$path" | head -1 | cut -d: -f1)"
    [[ -n "$first_line" && -n "$second_line" && "$first_line" -lt "$second_line" ]] || \
        fail "$path does not place $first before $second"
}

assets="$tmp/assets"
mkdir -p "$assets" "$tmp/bin" "$tmp/state"
printf 'archive bytes\n' >"$assets/Mori-test.zip"
printf '{"schemaVersion":1}\n' >"$assets/Mori-test.manifest.json"

cat >"$tmp/bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$GH_LOG"
[[ "$1" == api ]] || exit 64
shift
endpoint=""
input=""
jq=""
method="GET"
field_ref=""
field_sha=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --method) method="$2"; shift ;;
        --input) input="$2"; shift ;;
        --jq) jq="$2"; shift ;;
        -f|--raw-field)
            case "$2" in
                ref=*) field_ref="${2#ref=}" ;;
                sha=*) field_sha="${2#sha=}" ;;
            esac
            shift
            ;;
        repos/*|https://uploads.github.com/repos/*) endpoint="$1" ;;
    esac
    shift
done

if [[ "$endpoint" == */releases/tags/* ]]; then
    if [[ "${GH_SCENARIO:-}" == tag-exists ]]; then
        printf '{"id":9}\n'
        exit 0
    fi
    if [[ "${GH_SCENARIO:-}" == release-query-error ]]; then
        echo 'gh: Service Unavailable (HTTP 503)' >&2
        exit 1
    fi
    echo 'gh: Not Found (HTTP 404)' >&2
    exit 1
fi
if [[ "$endpoint" == */git/refs && "$method" == POST ]]; then
    [[ "${GH_SCENARIO:-}" != tag-race ]] || { echo 'gh: Reference already exists (HTTP 422)' >&2; exit 1; }
    printf '%s\t%s\n' "$field_ref" "$field_sha" >"$GH_STATE/ref"
    printf '{"ref":"%s","object":{"type":"commit","sha":"%s"}}\n' "$field_ref" "$field_sha"
    exit 0
fi
if [[ "$endpoint" == */git/refs/tags/* && "$method" == DELETE ]]; then
    rm -f "$GH_STATE/ref"
    exit 0
fi
if [[ "$endpoint" == */git/ref/tags/* ]]; then
    [[ "${GH_SCENARIO:-}" != ref-query-error ]] || { echo 'gh: Service Unavailable (HTTP 503)' >&2; exit 1; }
    [[ -f "$GH_STATE/ref" ]] || { echo 'gh: Not Found (HTTP 404)' >&2; exit 1; }
    ref_sha="$(cut -f2 "$GH_STATE/ref")"
    if [[ -n "$jq" ]]; then printf 'commit\t%s\n' "$ref_sha"; else printf '{"object":{"type":"commit","sha":"%s"}}\n' "$ref_sha"; fi
    exit 0
fi
if [[ "$endpoint" == */immutable-releases ]]; then
    if [[ -n "$jq" ]]; then printf 'true\n'; else printf '{"enabled":true}\n'; fi
    exit 0
fi
if [[ "$endpoint" == */releases/latest ]]; then
    printf 'v0.0.1\n'
    exit 0
fi
if [[ "$method" == POST && "$endpoint" == */releases ]]; then
    : >"$GH_STATE/draft"
    printf '{"id":42,"draft":true}\n'
    exit 0
fi
if [[ "$method" == POST && "$endpoint" == https://uploads.github.com/*/releases/42/assets?name=* ]]; then
    name="${endpoint##*name=}"
    digest="$(shasum -a 256 "$input" | awk '{print $1}')"
    printf '%s\t%s\t%s\n' "$name" "$digest" "$input" >> "$GH_STATE/assets"
    exit 0
fi
if [[ "$endpoint" == */releases/assets/* ]]; then
    asset_id="${endpoint##*/}"
    line="$(sed -n "${asset_id}p" "$GH_STATE/assets")"
    path="$(printf '%s' "$line" | cut -f3-)"
    cat "$path"
    exit 0
fi
if [[ "$endpoint" == */releases/42 && "$method" == PATCH ]]; then
    grep -Fq '"draft":false' "$input"
    : >"$GH_STATE/published"
    printf '{"id":42,"draft":false,"immutable":true}\n'
    exit 0
fi
if [[ "$endpoint" == */releases/42 && "$method" == DELETE ]]; then
    : >"$GH_STATE/deleted"
    exit 0
fi
if [[ "$endpoint" == */releases/42 ]]; then
    if [[ -n "$jq" ]]; then
        printf 'true\n'
        exit 0
    fi
    python3 - "$GH_STATE/assets" "${GH_SCENARIO:-}" <<'PY'
import json
import sys
assets = []
with open(sys.argv[1], encoding="utf-8") as stream:
    for number, line in enumerate(stream, 1):
        name, digest, _ = line.rstrip("\n").split("\t", 2)
        if sys.argv[2] == "digest-mismatch":
            digest = ("a" if digest[0] != "a" else "b") + digest[1:]
        assets.append({"id": number, "name": name, "digest": "sha256:" + digest})
print(json.dumps({"id": 42, "draft": True, "immutable": False, "assets": assets}))
PY
    exit 0
fi
echo "unexpected gh api request: $method $endpoint" >&2
exit 65
GH
chmod +x "$tmp/bin/gh"

run_draft() {
    env PATH="$tmp/bin:$PATH" GH_LOG="$tmp/gh.log" GH_STATE="$tmp/state" "$repo_root/scripts/github-release-draft.sh" "$@"
}

# A normal release verifies two server/downloaded asset digests before the sole publish request.
: >"$tmp/gh.log"
created="$(run_draft --create-draft --repo example/mori --tag v0.0.2 --target abc123 --title Test \
  --generate-notes --make-latest true --require-immutable \
  --asset "$assets/Mori-test.zip" --asset "$assets/Mori-test.manifest.json")"
[[ "$created" == 'release_id=42' ]] || fail "draft did not return its release id"
run_draft --publish-draft --repo example/mori --release-id 42 --require-immutable
[[ -f "$tmp/state/published" ]] || fail "draft was not published"
upload_line="$(grep -n '/assets?name=' "$tmp/gh.log" | tail -1 | cut -d: -f1)"
publish_line="$(grep -n 'PATCH repos/example/mori/releases/42' "$tmp/gh.log" | cut -d: -f1)"
[[ -n "$upload_line" && -n "$publish_line" && "$upload_line" -lt "$publish_line" ]] || fail "publish occurred before all uploads"
[[ "$(grep -c 'PATCH repos/example/mori/releases/42' "$tmp/gh.log")" -eq 1 ]] || fail "release was published more than once"

# Existing tags are a hard stop and cannot create or overwrite a release.
rm -rf "$tmp/state" && mkdir -p "$tmp/state"
: >"$tmp/gh.log"
expect_reject "an existing tag" env GH_SCENARIO=tag-exists PATH="$tmp/bin:$PATH" GH_LOG="$tmp/gh.log" GH_STATE="$tmp/state" \
  "$repo_root/scripts/github-release-draft.sh" --create-draft --repo example/mori --tag v0.0.2 --target abc123 --title Test \
  --asset "$assets/Mori-test.zip"
assert_not_contains "$tmp/gh.log" 'POST repos/example/mori/releases'

# A mismatched server digest cleans the still-mutable draft and never publishes it.
rm -rf "$tmp/state" && mkdir -p "$tmp/state"
: >"$tmp/gh.log"
expect_reject "a mismatched server digest" env GH_SCENARIO=digest-mismatch PATH="$tmp/bin:$PATH" GH_LOG="$tmp/gh.log" GH_STATE="$tmp/state" \
  "$repo_root/scripts/github-release-draft.sh" --create-draft --repo example/mori --tag v0.0.3 --target abc123 --title Test \
  --asset "$assets/Mori-test.zip"
assert_contains "$tmp/gh.log" 'DELETE repos/example/mori/releases/42'
assert_not_contains "$tmp/gh.log" 'PATCH repos/example/mori/releases/42'

# A non-publishing preflight downloads both assets, proves Latest is stable, and deletes its draft.
rm -rf "$tmp/state" && mkdir -p "$tmp/state"
: >"$tmp/gh.log"
run_draft --preflight --repo example/mori --tag release-draft-preflight-1 --target abc123 --title Preflight \
  --make-latest false --download-assets --asset "$assets/Mori-test.zip" --asset "$assets/Mori-test.manifest.json" >/dev/null
assert_contains "$tmp/gh.log" 'repos/example/mori/releases/latest'
[[ "$(grep -c 'repos/example/mori/releases/latest' "$tmp/gh.log")" -eq 2 ]] || fail "preflight did not compare Latest before and after"
[[ "$(grep -c 'repos/example/mori/releases/assets/' "$tmp/gh.log")" -eq 2 ]] || fail "preflight did not download both assets"
assert_contains "$tmp/gh.log" 'DELETE repos/example/mori/releases/42'
assert_not_contains "$tmp/gh.log" 'PATCH repos/example/mori/releases/42'

# Publisher atomically reserves a lightweight tag, verifies ownership, and only
# removes its own unpublished reservation.
tag_script="$repo_root/scripts/github-tag-reservation.sh"
reserved_sha="0123456789abcdef0123456789abcdef01234567"
rm -rf "$tmp/state" && mkdir -p "$tmp/state"
: >"$tmp/gh.log"
env PATH="$tmp/bin:$PATH" GH_LOG="$tmp/gh.log" GH_STATE="$tmp/state" \
  "$tag_script" --reserve --repo example/mori --tag ghosttykit-deadbeef-r1 --sha "$reserved_sha" >/dev/null
env PATH="$tmp/bin:$PATH" GH_LOG="$tmp/gh.log" GH_STATE="$tmp/state" \
  "$tag_script" --verify --repo example/mori --tag ghosttykit-deadbeef-r1 --sha "$reserved_sha"
env PATH="$tmp/bin:$PATH" GH_LOG="$tmp/gh.log" GH_STATE="$tmp/state" \
  "$tag_script" --cleanup --repo example/mori --tag ghosttykit-deadbeef-r1 --sha "$reserved_sha" >/dev/null
[[ ! -f "$tmp/state/ref" ]] || fail "cleanup left the unpublished reserved tag"
rm -rf "$tmp/state" && mkdir -p "$tmp/state"
expect_reject "a tag reservation race" env GH_SCENARIO=tag-race PATH="$tmp/bin:$PATH" GH_LOG="$tmp/gh.log" GH_STATE="$tmp/state" \
  "$tag_script" --reserve --repo example/mori --tag ghosttykit-deadbeef-r1 --sha "$reserved_sha"

# A transient release lookup failure must preserve the reserved tag because the
# publish request may have succeeded server-side.
rm -rf "$tmp/state" && mkdir -p "$tmp/state"
: >"$tmp/gh.log"
env PATH="$tmp/bin:$PATH" GH_LOG="$tmp/gh.log" GH_STATE="$tmp/state" \
  "$tag_script" --reserve --repo example/mori --tag ghosttykit-deadbeef-r1 --sha "$reserved_sha" >/dev/null
expect_reject "tag cleanup after an inconclusive release query" env GH_SCENARIO=release-query-error PATH="$tmp/bin:$PATH" GH_LOG="$tmp/gh.log" GH_STATE="$tmp/state" \
  "$tag_script" --cleanup --repo example/mori --tag ghosttykit-deadbeef-r1 --sha "$reserved_sha"
[[ -f "$tmp/state/ref" ]] || fail "inconclusive release query deleted the reserved tag"
assert_not_contains "$tmp/gh.log" 'DELETE repos/example/mori/git/refs/tags/ghosttykit-deadbeef-r1'

# Reservation ownership is recorded immediately after POST. If the following
# verification GET fails transiently, a recovered cleanup can still remove the
# unpublished tag.
rm -rf "$tmp/state" && mkdir -p "$tmp/state"
env PATH="$tmp/bin:$PATH" GH_LOG="$tmp/gh.log" GH_STATE="$tmp/state" \
  "$tag_script" --reserve --repo example/mori --tag ghosttykit-deadbeef-r1 --sha "$reserved_sha" >/dev/null
expect_reject "a transient post-reservation ownership lookup" env GH_SCENARIO=ref-query-error PATH="$tmp/bin:$PATH" GH_LOG="$tmp/gh.log" GH_STATE="$tmp/state" \
  "$tag_script" --verify --repo example/mori --tag ghosttykit-deadbeef-r1 --sha "$reserved_sha"
env PATH="$tmp/bin:$PATH" GH_LOG="$tmp/gh.log" GH_STATE="$tmp/state" \
  "$tag_script" --cleanup --repo example/mori --tag ghosttykit-deadbeef-r1 --sha "$reserved_sha" >/dev/null
[[ ! -f "$tmp/state/ref" ]] || fail "recovered cleanup left the unpublished reserved tag"

release="$repo_root/.github/workflows/release.yml"
preflight="$repo_root/.github/workflows/release-draft-preflight.yml"
publisher="$repo_root/.github/workflows/publish-ghosttykit.yml"
assert_not_contains "$release" 'softprops/action-gh-release'
assert_contains "$release" '--require-immutable'
assert_order "$release" 'Create and verify draft release' 'Publish complete immutable release'
assert_order "$release" 'Publish complete immutable release' 'Resolve release metadata'
assert_not_contains "$preflight" '--publish-draft'
assert_contains "$preflight" '--download-assets'
assert_contains "$preflight" 'workflow_dispatch:'
source "$repo_root/scripts/ghosttykit-contract.sh"
ghosttykit_load_contract "$repo_root/ghosttykit-lock.json"
[[ "$MORI_GHOSTTYKIT_ARTIFACT_TAG" == "ghosttykit-${MORI_GHOSTTYKIT_SOURCE_COMMIT:0:8}-r${MORI_GHOSTTYKIT_BUILD_REVISION}" ]] || \
    fail "GhosttyKit tag is not derived from the lock source and revision"
[[ "$MORI_GHOSTTYKIT_ARTIFACT_NAME" == "GhosttyKit-${MORI_GHOSTTYKIT_SOURCE_COMMIT:0:8}-r${MORI_GHOSTTYKIT_BUILD_REVISION}-universal.zip" ]] || \
    fail "GhosttyKit asset name is not derived from the lock source and revision"
assert_contains "$publisher" 'environment: ghosttykit-publish'
assert_contains "$publisher" 'contents: write'
assert_contains "$publisher" 'id-token: write'
assert_contains "$publisher" 'attestations: write'
python3 - "$publisher" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
match = re.search(r"^permissions:\n((?:  [^\n]+\n)+)\nconcurrency:", text, re.M)
if not match:
    raise SystemExit("publisher permissions block is missing or not top-level")
actual = {line.strip() for line in match.group(1).splitlines()}
expected = {"contents: write", "id-token: write", "attestations: write"}
if actual != expected:
    raise SystemExit(f"publisher permissions must be exactly {expected}, got {actual}")
if "actions/cache" in text:
    raise SystemExit("publisher must not restore a finished-framework cache")
PY
assert_contains "$publisher" 'submodules: recursive'
assert_contains "$publisher" 'fetch-depth: 0'
assert_contains "$publisher" 'git ls-remote --exit-code --tags'
assert_contains "$publisher" 'scripts/install-verified-zig.sh'
assert_contains "$publisher" 'scripts/build-ghostty.sh --clean --universal'
assert_contains "$publisher" 'actions/attest-build-provenance@v3'
assert_contains "$repo_root/scripts/github-release-draft.sh" 'https://uploads.github.com/repos/'
assert_order "$publisher" 'Attest GhosttyKit archive' 'Atomically reserve the release tag'
assert_order "$publisher" 'Atomically reserve the release tag' 'Verify reserved tag ownership'
assert_order "$publisher" 'Verify reserved tag ownership' 'Create and upload draft release'
assert_order "$publisher" 'Create and upload draft release' 'Verify server digests and uploaded bytes'
assert_order "$publisher" 'Verify server digests and uploaded bytes' 'Publish immutable GhosttyKit release once'
assert_contains "$publisher" 'Delete incomplete draft and reserved tag'
assert_contains "$release" 'Verify release event tag ownership'

printf '✅ Release draft flow rejects overwrite, verifies multi-asset drafts, and publishes only once\n'
