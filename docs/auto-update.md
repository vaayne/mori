# Auto-Update System

Mori uses [Sparkle 2](https://sparkle-project.org/) for in-app auto-updates. Updates are distributed via an appcast XML feed hosted on GitHub Pages and signed with EdDSA (Ed25519).

## EdDSA Key Setup

Sparkle uses EdDSA (Ed25519) signatures to verify update archives. You need a keypair: the public key is embedded in the app bundle's `Info.plist`, and the private key is used by CI to sign release archives.

### Generate Keys

Use the `generate_keys` tool from Sparkle's SPM binary artifacts:

```bash
# From the Mori repo root (after `swift package resolve`)
.build/artifacts/sparkle/Sparkle/bin/generate_keys
```

This prints the **public key** to stdout and stores the private key in the macOS Keychain.

### Export Private Key

To export the private key for CI use:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x
```

This prints the base64-encoded private key. **Do not commit this value.**

### Store Keys

1. **Public key** — Replace `PLACEHOLDER_EDDSA_PUBLIC_KEY` in `scripts/bundle.sh` (the `SUPublicEDKey` value in Info.plist) with the generated public key string.

2. **Private key** — Store as a GitHub Actions secret named `SPARKLE_PRIVATE_KEY`. The CI release workflow passes this to `generate_appcast` for archive signing.

## Update Flow Overview

1. On app launch, `UpdateController` starts Sparkle's `SPUUpdater`.
2. Sparkle periodically checks the appcast feed at `https://vaayne.github.io/mori/appcast.xml`.
3. If a newer version is found, an update badge appears in the titlebar.
4. The user can click the badge to view release notes and install the update.
5. Sparkle downloads, verifies the EdDSA signature, extracts, and relaunches.

## CI Pipeline

The release workflow (`.github/workflows/release.yml`) generates and publishes the appcast automatically on every tagged release. The pipeline flow:

```
build Mori.app
    → create signed ZIP + DMG archives
    → generate appcast.xml (EdDSA-signed)
    → upload archives to GitHub Release
    → publish appcast.xml to gh-pages branch
    → update Homebrew tap
```

### How appcast.xml Is Generated

1. The `scripts/generate-appcast.sh` script downloads the Sparkle 2.9.0 release tarball from GitHub to obtain the `generate_appcast` and `sign_update` binaries (SPM artifacts are not available in CI runners).
2. The `SPARKLE_PRIVATE_KEY` secret is written to a temporary file (cleaned up on exit).
3. The signed ZIP archive is copied into a staging directory.
4. `generate_appcast` scans the archive, extracts version info from the embedded `Info.plist`, computes EdDSA signatures, and produces `appcast.xml`.
5. The appcast is uploaded as a GitHub Actions artifact, then the `publish-appcast` job checks out the `gh-pages` branch, copies the new `appcast.xml`, and pushes.

### How to Set Up the `SPARKLE_PRIVATE_KEY` Secret

1. Generate the EdDSA keypair (see [EdDSA Key Setup](#eddsa-key-setup) above).
2. Export the private key: `.build/artifacts/sparkle/Sparkle/bin/generate_keys -x`
3. Go to the repo's **Settings > Secrets and variables > Actions**.
4. Create a new repository secret named `SPARKLE_PRIVATE_KEY` with the base64-encoded private key value.

## Appcast Feed

The appcast XML is hosted on the `gh-pages` branch of the mori repository at:

```
https://vaayne.github.io/mori/appcast.xml
```

It is generated automatically by the release CI workflow using Sparkle's `generate_appcast` tool.

### Initialize the gh-pages Branch

The `gh-pages` branch must exist before the first release. Run the setup script:

```bash
bash scripts/setup-gh-pages.sh
git push -u origin gh-pages
git checkout main  # switch back
```

This creates an orphan branch with:
- `index.html` — redirects to the main GitHub repo page
- `appcast.xml` — empty placeholder (replaced by CI on first release)

Then enable GitHub Pages in **Settings > Pages > Source: gh-pages branch**.

### Manual Appcast Generation

To generate an appcast locally (e.g., for testing):

```bash
# Build and archive Mori.app first
MORI_VERSION="1.0.0" bash scripts/bundle.sh
ditto -c -k --norsrc --keepParent Mori.app "Mori-1.0.0-macos-arm64.zip"

# Generate appcast (requires the private key)
SPARKLE_PRIVATE_KEY="$(cat /path/to/private-key)" \
  bash scripts/generate-appcast.sh 1.0.0 Mori-1.0.0-macos-arm64.zip

# Inspect the output
cat appcast.xml
```

## Key Files

| File | Purpose |
|------|---------|
| `Package.swift` | Sparkle SPM dependency (`from: "2.7.0"`) |
| `scripts/bundle.sh` | Embeds Sparkle.framework, sets `SUPublicEDKey` and `SUFeedURL` in Info.plist |
| `scripts/sign.sh` | Signs Sparkle framework, XPC services, and app bundle |
| `Sources/Mori/Update/` | Update UI and controller logic |
| `scripts/generate-appcast.sh` | CI script to sign archives and generate appcast.xml |
| `scripts/setup-gh-pages.sh` | One-time script to initialize the gh-pages branch |
| `.github/workflows/release.yml` | Release workflow with appcast generation and gh-pages publish |

## Regenerating Keys

If the private key is lost or compromised:

1. Run `generate_keys` to create a new keypair.
2. Update `SUPublicEDKey` in `scripts/bundle.sh` with the new public key.
3. Export the new private key with `generate_keys -x` and update the `SPARKLE_PRIVATE_KEY` GitHub secret.
4. Re-sign and re-publish all existing release archives (users on old versions won't be able to verify new updates until they manually update).

## Troubleshooting

### Appcast not updating after release

- Check the `publish-appcast` job in the release workflow run. If it shows "appcast.xml unchanged", the `generate_appcast` tool may have failed silently.
- Verify `SPARKLE_PRIVATE_KEY` is set in repo secrets. The `generate-appcast.sh` script will fail with an explicit error if it's missing.
- Inspect the uploaded `appcast` artifact in the workflow run to confirm it contains valid XML.

### App not finding updates

- Verify the `SUFeedURL` in `scripts/bundle.sh` points to `https://vaayne.github.io/mori/appcast.xml`.
- Check that GitHub Pages is enabled on the `gh-pages` branch (Settings > Pages).
- Open the feed URL in a browser to confirm it returns valid XML.
- In Console.app, filter for "Sparkle" to see detailed update check logs.
- Clear the last check timestamp to force a re-check: `defaults delete com.mori.app SULastCheckTime`

### EdDSA signature verification failures

- Ensure the `SUPublicEDKey` in `scripts/bundle.sh` matches the private key used in CI.
- Run `generate_keys` (without flags) to display the public key for the current Keychain entry.
- If keys were regenerated, all existing archives must be re-signed and the appcast regenerated.

### generate_appcast fails in CI

- The script downloads Sparkle tools from GitHub Releases. If the download fails, check network connectivity and the Sparkle release URL.
- Ensure the archive contains a valid `Mori.app` with `Info.plist` (generate_appcast reads `CFBundleVersion` and `CFBundleShortVersionString` from it).
- Run the script locally with `SPARKLE_PRIVATE_KEY` set to diagnose.
