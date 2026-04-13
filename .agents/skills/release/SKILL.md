---
name: release
description: >
  Release workflow for Mori macOS workspace terminal and MoriRemote iOS app.
  Create releases with semantic versioned tags, update changelog, and trigger
  automated CI/CD builds. Use when the user asks to "release", "create a release",
  "tag a version", "update changelog", "prepare release", "cut a release",
  "publish to TestFlight", or discusses versioning and release artifacts.
---

# Release

## macOS Release

### Tag Format

Use semantic versioning with `v` prefix: `v0.1.0`, `v1.0.0`, `v1.2.3-rc.1`.

### Release Flow

1. Update `CHANGELOG.md` (see below)
2. Commit: `📝 docs: update CHANGELOG for vX.Y.Z`
3. Tag: `git tag vX.Y.Z`
4. Push: `git push origin main --tags`
5. CI triggers `.github/workflows/release.yml` → builds, signs, notarizes, and publishes the GitHub Release
6. CI updates `vaayne/homebrew-tap` with the new `mori` cask version and SHA-256

### Required Secrets

- `APPLE_CERTIFICATE_P12`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_PASSWORD`
- `APPLE_DEVELOPER_NAME`
- `HOMEBREW_TAP_TOKEN` — personal access token with write access to `vaayne/homebrew-tap`
- `SPARKLE_PRIVATE_KEY` — EdDSA key for Sparkle appcast signing

### Homebrew Tap

Homebrew does not automatically update a third-party tap from GitHub Releases. Mori's release workflow is responsible for updating `vaayne/homebrew-tap`.

The tap update flow:

1. Read the uploaded ZIP asset digest from the just-created GitHub Release
2. Rewrite `Casks/mori.rb` in `vaayne/homebrew-tap`
3. Commit and push the cask update to the tap's default branch

The generated cask installs `Mori.app`, depends on `tmux`, and exposes the embedded `mori` CLI via a `binary` stanza.

### Artifacts

- **macOS app ZIP**: `Mori-X.Y.Z-macos-arm64.zip` (signed and notarized)
- **macOS app DMG**: `Mori-X.Y.Z-macos-arm64.dmg` (signed and notarized)
- **GitHub Release**: Auto-created by `release.yml` workflow on tag push
- **Homebrew tap**: `vaayne/homebrew-tap` updated automatically after a successful release

---

## iOS Release (MoriRemote → TestFlight)

### Version Rule

For MoriRemote TestFlight uploads, keep the App Store Connect marketing version fixed at `0.3.5` unless the user explicitly asks to change it. New TestFlight uploads must reuse version `0.3.5` and only increment the build number.

### Tag Format

Use semantic versioning with `ios-v` prefix: `ios-v0.1.0`, `ios-v1.0.0`.

### Release Flow

**Option A: Manual dispatch (recommended for testing)**

```bash
gh workflow run release-ios.yml -R vaayne/mori \
  --ref <branch> \
  -f version=0.3.5 \
  -f build_number=N
```

**Option B: Tag-based**

1. Keep the TestFlight marketing version at `0.3.5` unless explicitly told otherwise
2. Tag: `git tag ios-vX.Y.Z`
3. Push: `git push origin ios-vX.Y.Z`
4. CI triggers `.github/workflows/release-ios.yml` → archives, exports IPA, uploads to TestFlight

### Required Secrets

- `IOS_CERTIFICATE_P12` — Apple Distribution certificate (base64-encoded .p12)
- `IOS_CERTIFICATE_PASSWORD` — password for the .p12
- `APPLE_ID` — Apple ID email (shared with macOS)
- `APPLE_APP_PASSWORD` — app-specific password (shared with macOS)
- `APPLE_TEAM_ID` — team ID (shared with macOS)

### App Store Connect

- **App Name**: MoriRemote
- **Bundle ID**: `com.vaayne.mori-remote`
- **Apple ID**: 6761400903
- **SKU**: `mori-remote`

### After Upload

1. Go to [App Store Connect → MoriRemote → TestFlight](https://appstoreconnect.apple.com/apps/6761400903/testflight)
2. Wait for Apple's processing (5–15 minutes)
3. Add testers under **Internal Testing** group
4. Testers receive a TestFlight invite on their device

### Artifacts

- **IPA**: uploaded to GitHub Actions as artifact (90-day retention)
- **TestFlight**: uploaded automatically via `xcrun altool`

---

## Update Changelog

The changelog lives at `CHANGELOG.md` in the repo root. It follows [Keep a Changelog](https://keepachangelog.com) format.

Gather changes since last tag:

```bash
git log $(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)..HEAD --oneline
gh pr list --state merged --base main --search "merged:>=$(git log -1 --format=%aI $(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD))"
```

Apply to `CHANGELOG.md`:

1. Rename `[Unreleased]` to `[X.Y.Z] - YYYY-MM-DD`
2. Add fresh `[Unreleased]` section above
3. Categorize: `✨ Features`, `🐛 Bug Fixes`, `♻️ Refactoring`, `📝 Documentation`, `📦 Dependencies`
4. Link PRs: `([#123](https://github.com/vaayne/mori/pull/123))`
5. Append: `**Full Changelog**: [vPREV...vX.Y.Z](https://github.com/vaayne/mori/compare/vPREV...vX.Y.Z)`
