#!/usr/bin/env bash
# setup-gh-pages.sh — Initialize the gh-pages branch for appcast hosting.
#
# This script creates an orphan gh-pages branch with:
#   - index.html (redirect to main repo)
#   - appcast.xml (empty placeholder)
#
# Run once from the repo root:
#   bash scripts/setup-gh-pages.sh
#
# After running, enable GitHub Pages in repo Settings → Pages → Source: gh-pages branch.

set -euo pipefail

REPO_URL="https://github.com/vaayne/mori"

# --- Safety check ---

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$CURRENT_BRANCH" == "gh-pages" ]]; then
  echo "Error: Already on gh-pages branch. Aborting." >&2
  exit 1
fi

# --- Check for uncommitted changes ---

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Error: You have uncommitted changes. Please commit or stash them first." >&2
  exit 1
fi

echo "Creating orphan gh-pages branch..."

# --- Create orphan branch ---

git checkout --orphan gh-pages

# Remove all tracked files from the index (but don't delete untracked files)
git rm -rf . > /dev/null 2>&1 || true

# --- Create index.html ---

cat > index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta http-equiv="refresh" content="0; url=https://github.com/vaayne/mori">
  <title>Mori</title>
</head>
<body>
  <p>Redirecting to <a href="https://github.com/vaayne/mori">Mori on GitHub</a>...</p>
  <p>Looking for the update feed? See <a href="appcast.xml">appcast.xml</a>.</p>
</body>
</html>
HTMLEOF

# --- Create empty appcast.xml placeholder ---

cat > appcast.xml << 'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Mori Updates</title>
    <link>https://vaayne.github.io/mori/appcast.xml</link>
    <description>Appcast feed for Mori auto-updates.</description>
    <language>en</language>
  </channel>
</rss>
XMLEOF

# --- Commit and push ---

git add index.html appcast.xml
git commit -m "Initialize gh-pages with appcast placeholder"

echo ""
echo "gh-pages branch created locally. To publish:"
echo "  git push -u origin gh-pages"
echo ""
echo "Then switch back to your working branch:"
echo "  git checkout ${CURRENT_BRANCH}"
echo ""
echo "Finally, enable GitHub Pages in repo Settings → Pages → Source: gh-pages branch."
