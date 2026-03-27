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

## Appcast Feed

The appcast XML is hosted on the `gh-pages` branch of the mori repository at:

```
https://vaayne.github.io/mori/appcast.xml
```

It is generated automatically by the release CI workflow using Sparkle's `generate_appcast` tool.

## Key Files

| File | Purpose |
|------|---------|
| `Package.swift` | Sparkle SPM dependency (`from: "2.7.0"`) |
| `scripts/bundle.sh` | Embeds Sparkle.framework, sets `SUPublicEDKey` and `SUFeedURL` in Info.plist |
| `scripts/sign.sh` | Signs Sparkle framework, XPC services, and app bundle |
| `Sources/Mori/Update/` | Update UI and controller logic |
| `scripts/generate-appcast.sh` | CI script to sign archives and generate appcast.xml (Phase 5) |

## Regenerating Keys

If the private key is lost or compromised:

1. Run `generate_keys` to create a new keypair.
2. Update `SUPublicEDKey` in `scripts/bundle.sh` with the new public key.
3. Export the new private key with `generate_keys -x` and update the `SPARKLE_PRIVATE_KEY` GitHub secret.
4. Re-sign and re-publish all existing release archives (users on old versions won't be able to verify new updates until they manually update).
