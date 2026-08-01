#!/usr/bin/env bash
# Install the lock-pinned macOS Zig toolchain only after verifying its archive.
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=ghosttykit-contract.sh
source "$project_root/scripts/ghosttykit-contract.sh"
ghosttykit_load_contract "$project_root/ghosttykit-lock.json"

prefix="${RUNNER_TEMP:-$project_root/.derived-data}/zig"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)
            [[ $# -ge 2 ]] || { echo "Usage: $0 [--prefix DIRECTORY]" >&2; exit 2; }
            prefix="$2"
            shift
            ;;
        *)
            echo "Usage: $0 [--prefix DIRECTORY]" >&2
            exit 2
            ;;
    esac
    shift
done

[[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]] || {
    echo "Verified Zig installer currently supports only macOS arm64 runners." >&2
    exit 1
}

prefix="$(mkdir -p "$prefix" && cd "$prefix" && pwd -P)"
archive="${RUNNER_TEMP:-$prefix}/zig-aarch64-macos-${MORI_GHOSTTYKIT_ZIG_VERSION}.tar.xz"
extract_root="${RUNNER_TEMP:-$prefix}/zig-aarch64-macos-${MORI_GHOSTTYKIT_ZIG_VERSION}"
url="https://ziglang.org/download/${MORI_GHOSTTYKIT_ZIG_VERSION}/zig-aarch64-macos-${MORI_GHOSTTYKIT_ZIG_VERSION}.tar.xz"

rm -f "$archive"
rm -rf "$extract_root" "$prefix/bin" "$prefix/lib"
curl -fSL "$url" -o "$archive"
printf '%s  %s\n' "$MORI_GHOSTTYKIT_ZIG_ARCHIVE_SHA256" "$archive" | shasum -a 256 -c - >&2
tar xf "$archive" -C "$(dirname "$extract_root")"
[[ -x "$extract_root/zig" && -d "$extract_root/lib" ]] || {
    echo "Verified Zig archive has an unexpected layout." >&2
    exit 1
}
mkdir -p "$prefix/bin"
cp "$extract_root/zig" "$prefix/bin/zig"
cp -R "$extract_root/lib" "$prefix/lib"
[[ "$("$prefix/bin/zig" version)" == "$MORI_GHOSTTYKIT_ZIG_VERSION" ]] || {
    echo "Verified Zig installation reports the wrong version." >&2
    exit 1
}
printf '%s\n' "$prefix/bin"
