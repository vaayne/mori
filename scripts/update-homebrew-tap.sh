#!/bin/bash
set -euo pipefail

VERSION="${VERSION:?VERSION is required}"
SHA256="${SHA256:?SHA256 is required}"
TAP_DIR="${TAP_DIR:?TAP_DIR is required}"

CASK_PATH="${TAP_DIR}/Casks/mori.rb"

mkdir -p "${TAP_DIR}/Casks"

cat > "${CASK_PATH}" <<EOF
cask "mori" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "https://github.com/vaayne/mori/releases/download/v#{version}/Mori-#{version}-macos-arm64.zip"
  name "Mori"
  desc "Native macOS workspace terminal organized around projects and worktrees"
  homepage "https://github.com/vaayne/mori"

  depends_on arch: :arm64
  depends_on macos: ">= :sonoma"
  depends_on formula: "tmux"

  app "Mori.app"
  binary "#{appdir}/Mori.app/Contents/MacOS/bin/mori", target: "mori"

  zap trash: [
    "~/Library/Application Support/Mori",
    "~/Library/Preferences/com.mori.app.plist",
    "~/Library/Preferences/dev.mori.app.plist",
    "~/Library/Preferences/dev.mori.shared.plist",
    "~/Library/Saved Application State/dev.mori.app.savedState",
  ]
end
EOF
