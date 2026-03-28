# Auto-Update System

Mori uses [Sparkle 2](https://sparkle-project.org/) for in-app auto-updates. Updates are distributed via an appcast XML feed hosted in the [homebrew-tap](https://github.com/vaayne/homebrew-tap) repository and signed with EdDSA (Ed25519).

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
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x /tmp/sparkle_key.txt
cat /tmp/sparkle_key.txt
rm /tmp/sparkle_key.txt
```

This writes the base64-encoded private key to a file. **Do not commit this value.**

### Store Keys

1. **Public key** — Set in `scripts/bundle.sh` (the `SUPublicEDKey` value in Info.plist).

2. **Private key** — Store as a GitHub Actions secret named `SPARKLE_PRIVATE_KEY`. The CI release workflow passes this to `generate_appcast` for archive signing.

## Update Flow Overview

1. On app launch, `UpdateController` starts Sparkle's `SPUUpdater`.
2. Sparkle periodically checks the appcast feed at `https://raw.githubusercontent.com/vaayne/homebrew-tap/main/mori-appcast.xml`.
3. If a newer version is found, an update badge appears in the titlebar.
4. The user can click the badge to view release notes and install the update.
5. Sparkle downloads, verifies the EdDSA signature, extracts, and relaunches.

## CI Pipeline

The release workflow (`.github/workflows/release.yml`) generates and publishes the appcast automatically on every tagged release. The pipeline flow:

```
build Mori.app
    → create signed ZIP + DMG archives
    → generate mori-appcast.xml (EdDSA-signed)
    → upload archives to GitHub Release
    → update Homebrew tap + mori-appcast.xml in vaayne/homebrew-tap
```

### How mori-appcast.xml Is Generated

1. The `scripts/generate-appcast.sh` script downloads the Sparkle 2.9.0 release tarball from GitHub to obtain the `generate_appcast` and `sign_update` binaries.
2. The `SPARKLE_PRIVATE_KEY` secret is written to a temporary file (cleaned up on exit).
3. The signed ZIP archive is copied into a staging directory.
4. `generate_appcast` scans the archive, extracts version info from the embedded `Info.plist`, computes EdDSA signatures, and produces `mori-appcast.xml`.
5. The appcast is committed to the `vaayne/homebrew-tap` repo alongside the Homebrew cask update.

### How to Set Up the `SPARKLE_PRIVATE_KEY` Secret

1. Generate the EdDSA keypair (see [EdDSA Key Setup](#eddsa-key-setup) above).
2. Export the private key to a file.
3. Go to the repo's **Settings > Secrets and variables > Actions**.
4. Create a new repository secret named `SPARKLE_PRIVATE_KEY` with the base64-encoded private key value.

## Appcast Feed

The appcast XML is hosted in the `vaayne/homebrew-tap` repository at:

```
https://raw.githubusercontent.com/vaayne/homebrew-tap/main/mori-appcast.xml
```

It is updated automatically by the release CI workflow using Sparkle's `generate_appcast` tool, in the same commit that updates the Homebrew cask.

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
cat mori-appcast.xml
```

## Key Files

| File | Purpose |
|------|---------|
| `Package.swift` | Sparkle SPM dependency (`from: "2.7.0"`) |
| `scripts/bundle.sh` | Embeds Sparkle.framework, sets `SUPublicEDKey` and `SUFeedURL` in Info.plist |
| `scripts/sign.sh` | Signs Sparkle framework, XPC services, and app bundle |
| `Sources/Mori/Update/` | Update UI and controller logic |
| `scripts/generate-appcast.sh` | CI script to sign archives and generate mori-appcast.xml |
| `.github/workflows/release.yml` | Release workflow with appcast generation |

## Regenerating Keys

If the private key is lost or compromised:

1. Run `generate_keys` to create a new keypair.
2. Update `SUPublicEDKey` in `scripts/bundle.sh` with the new public key.
3. Export the new private key and update the `SPARKLE_PRIVATE_KEY` GitHub secret.
4. Re-sign and re-publish all existing release archives (users on old versions won't be able to verify new updates until they manually update).

## Troubleshooting

### Appcast not updating after release

- Check the `update-homebrew-tap` job in the release workflow run.
- Verify `SPARKLE_PRIVATE_KEY` is set in repo secrets. The `generate-appcast.sh` script will fail with an explicit error if it's missing.
- Inspect the uploaded `appcast` artifact in the workflow run to confirm it contains valid XML.

### App not finding updates

- Verify the `SUFeedURL` in `scripts/bundle.sh` points to `https://raw.githubusercontent.com/vaayne/homebrew-tap/main/mori-appcast.xml`.
- Open the feed URL in a browser to confirm it returns valid XML.
- In Console.app, filter for "Sparkle" to see detailed update check logs.
- Clear the last check timestamp to force a re-check: `defaults delete dev.mori.app SULastCheckTime`

### EdDSA signature verification failures

- Ensure the `SUPublicEDKey` in `scripts/bundle.sh` matches the private key used in CI.
- Run `generate_keys` (without flags) to display the public key for the current Keychain entry.
- If keys were regenerated, all existing archives must be re-signed and the appcast regenerated.

### generate_appcast fails in CI

- The script downloads Sparkle tools from GitHub Releases. If the download fails, check network connectivity and the Sparkle release URL.
- Ensure the archive contains a valid `Mori.app` with `Info.plist` (generate_appcast reads `CFBundleVersion` and `CFBundleShortVersionString` from it).
- Run the script locally with `SPARKLE_PRIVATE_KEY` set to diagnose.
