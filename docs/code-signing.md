# Code Signing & Notarization

This guide covers everything needed to sign and notarize Mori for macOS distribution outside the App Store.

## Prerequisites

- **Apple Developer Program** membership ($99/year) — [developer.apple.com/programs](https://developer.apple.com/programs)
  - Free accounts do NOT have access to Developer ID certificates
- **Xcode** installed (for command-line tools)
- **macOS Keychain Access** (built-in)

## 1. Create a Developer ID Application Certificate

This certificate is required to sign apps for distribution outside the Mac App Store.

### 1.1 Generate a Certificate Signing Request (CSR)

The CSR creates a **private key** on your machine and a request file to send to Apple. The private key never leaves your machine — Apple uses the CSR to issue a certificate that pairs with it.

> **Critical**: You MUST generate the CSR on the same machine where you will sign apps. The private key is stored in your macOS Keychain during CSR generation. If you install a certificate on a machine that doesn't have the matching private key, `security find-identity` will not show it as a valid codesigning identity.

1. Open **Keychain Access** (Applications > Utilities > Keychain Access)
2. Menu bar: **Keychain Access** > **Certificate Assistant** > **Request a Certificate From a Certificate Authority...**
3. Fill in the dialog:
   - **User Email Address**: your Apple ID email (e.g. `you@example.com`)
   - **Common Name**: your full name (e.g. "Wei Liu") — this appears in the certificate
   - **CA Email Address**: leave blank
   - **Request is**: select **Saved to disk**
4. Click **Continue** and save the `.certSigningRequest` file somewhere you can find it (e.g. Desktop)

What happens behind the scenes:
- A 2048-bit RSA key pair is generated
- The **private key** is stored in your **login** keychain (Keychain Access > login > Keys — look for a key matching your Common Name)
- The **public key** is embedded in the `.certSigningRequest` file

### 1.2 Create the Certificate on Apple Developer Portal

1. Go to [developer.apple.com/account/resources/certificates/add](https://developer.apple.com/account/resources/certificates/add)
2. Under **Software**, select **Developer ID Application**
   - This option is only available with a paid Apple Developer Program membership
   - Do NOT select "Apple Development" or "Apple Distribution" — those are for App Store only
3. Click **Continue**
4. If prompted to select a **Developer ID Certificate Authority**, choose **Developer ID - G2 (Expiring 09/17/2031)** (the newer one)
5. Click **Choose File** and upload the `.certSigningRequest` file from step 1.1
6. Click **Continue**
7. Click **Download** to get the `.cer` file

### 1.3 Install the Certificate

1. Double-click the downloaded `.cer` file — it opens in Keychain Access automatically
2. It installs to your **login** keychain and pairs with the private key from step 1.1
3. Verify it's installed and paired correctly:

```bash
security find-identity -v -p codesigning
```

You should see output like:

```
1) ABCDEF1234... "Developer ID Application: Wei Liu (ABC1234DEF)"
     1 valid identities found
```

The full string in quotes is your **`SIGNING_IDENTITY`**. The 10-character code in parentheses is your **Team ID**.

4. In **Keychain Access**, expand the certificate (click the triangle) — you should see a **private key** nested under it. If there's no private key, see troubleshooting below.

### 1.4 Troubleshooting: Certificate Not Showing Up

**Symptom**: You installed the `.cer` but `security find-identity -v -p codesigning` doesn't list "Developer ID Application".

**Cause**: The certificate can't find its matching private key. This happens when:
- The CSR was generated on a **different machine**
- The private key was **deleted** from the keychain
- The certificate was installed in a **different keychain** (e.g. System instead of login)

**Fix**:

```bash
# Check if the cert is installed at all (even without valid signing)
security find-identity -v

# Check a specific keychain
security find-identity -v -p codesigning ~/Library/Keychains/login.keychain-db
```

Open **Keychain Access** > **login** keychain > **Certificates** tab > find the Developer ID certificate > expand it. If no private key is shown, you need to start over:

1. **Revoke** the certificate at [developer.apple.com/account/resources/certificates/list](https://developer.apple.com/account/resources/certificates/list)
2. Generate a **new CSR** on this machine (step 1.1)
3. Create a **new** Developer ID Application certificate with the new CSR (step 1.2)
4. Install the new `.cer` (step 1.3)

### 1.5 Back Up Your Certificate + Private Key

If you lose the private key, you'll need to revoke and recreate the certificate. Export a backup:

1. Open **Keychain Access** > **login** keychain > **Certificates**
2. Right-click your "Developer ID Application" certificate > **Export...**
3. Choose format **Personal Information Exchange (.p12)**
4. Set a strong password
5. Store the `.p12` file securely (e.g. password manager, encrypted drive)

To restore on another machine or after a reinstall, double-click the `.p12` file and enter the password — it imports both the certificate and private key.

> **Note**: "Apple Development" and "Apple Distribution" certificates (available in Xcode) are for App Store distribution and development. They will NOT work for distributing outside the App Store.

## 2. Create an App-Specific Password

Apple requires an app-specific password for notarization (your regular Apple ID password won't work).

1. Go to [account.apple.com](https://account.apple.com)
2. Sign in with your Apple ID
3. Navigate to **Sign-In and Security** > **App-Specific Passwords**
4. Click **Generate an app-specific password** (or the **+** button)
5. Enter a label, e.g. `mori-notarize`
6. Copy the generated password (format: `xxxx-xxxx-xxxx-xxxx`)

> **Important**: Save this password somewhere secure. You can only see it once.

## 3. Find Your Team ID

Your Team ID is the 10-character alphanumeric identifier for your Apple Developer account.

### Option A: From the certificate

```bash
security find-identity -v -p codesigning | grep "Developer ID"
```

The Team ID is in parentheses: `Developer ID Application: Your Name (TEAM_ID_HERE)`

### Option B: From the developer portal

Go to [developer.apple.com/account](https://developer.apple.com/account) > **Membership details** > **Team ID**

## 4. Store Notarization Credentials

Store your credentials in the macOS Keychain so they don't need to be entered repeatedly:

```bash
xcrun notarytool store-credentials "mori-notarize" \
  --apple-id "your-apple-id@email.com" \
  --team-id "ABC1234DEF" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

Replace:
- `your-apple-id@email.com` — your Apple ID email
- `ABC1234DEF` — your Team ID from step 3
- `xxxx-xxxx-xxxx-xxxx` — your app-specific password from step 2

Verify the credentials work:

```bash
xcrun notarytool history --keychain-profile "mori-notarize"
```

This should return without errors (empty history is fine).

## 5. Sign and Notarize Locally

### Quick build (signed + notarized)

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (ABC1234DEF)" \
KEYCHAIN_PROFILE="mori-notarize" \
mise run bundle
```

### Quick build (signed only, no notarization)

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (ABC1234DEF)" \
mise run bundle
```

### Quick build (unsigned, for local development)

```bash
mise run bundle
```

### Manual signing (if you already have a built .app)

```bash
# Sign only
SIGNING_IDENTITY="Developer ID Application: Your Name (ABC1234DEF)" \
bash scripts/sign.sh

# Sign + notarize
SIGNING_IDENTITY="Developer ID Application: Your Name (ABC1234DEF)" \
KEYCHAIN_PROFILE="mori-notarize" \
bash scripts/sign.sh --notarize
```

### Verify the result

```bash
# Check code signature
codesign --verify --deep --strict --verbose=2 Mori.app

# Check notarization staple
stapler validate Mori.app

# Check Gatekeeper acceptance
spctl --assess --type execute --verbose=2 Mori.app
```

## 6. GitHub Actions (CI/CD)

The release workflow automatically signs and notarizes when the required secrets are configured.

### 6.1 Export Your Certificate as .p12

1. Open **Keychain Access**
2. Find your "Developer ID Application" certificate in the **login** keychain
3. Right-click the certificate > **Export...**
4. Choose **Personal Information Exchange (.p12)** format
5. Set a strong password and save the file

### 6.2 Base64-Encode the .p12

```bash
base64 -i certificate.p12 | pbcopy
```

This copies the base64 string to your clipboard.

### 6.3 Add GitHub Repository Secrets

Go to your repo on GitHub > **Settings** > **Secrets and variables** > **Actions** > **New repository secret**

Add each of these secrets:

| Secret Name | Value | Example |
|---|---|---|
| `APPLE_CERTIFICATE_P12` | Base64-encoded .p12 from step 6.2 | `MIIKYwIBAzCCCi...` |
| `APPLE_CERTIFICATE_PASSWORD` | The password you set when exporting .p12 | `your-p12-password` |
| `APPLE_DEVELOPER_NAME` | Your name exactly as it appears in the certificate | `Wei Liu` |
| `APPLE_TEAM_ID` | Your 10-character Team ID | `ABC1234DEF` |
| `APPLE_ID` | Your Apple ID email | `you@example.com` |
| `APPLE_APP_PASSWORD` | App-specific password from step 2 | `xxxx-xxxx-xxxx-xxxx` |

### 6.4 How It Works

When a release tag (`v*`) is pushed:

1. **Certificate import**: The .p12 is decoded and imported into a temporary keychain on the runner
2. **Credentials stored**: `notarytool store-credentials` saves auth to the runner's keychain
3. **Build + sign**: `bundle.sh` builds the app and calls `sign.sh` to sign with hardened runtime
4. **Notarize**: The signed app is submitted to Apple's notary service (waits for approval)
5. **Staple**: The notarization ticket is stapled to the app bundle
6. **Archive**: The signed, notarized app is zipped and attached to the GitHub Release
7. **Cleanup**: The temporary keychain is deleted

## 7. Entitlements

The `Mori.entitlements` file grants the following permissions:

| Entitlement | Why |
|---|---|
| `com.apple.security.automation.apple-events` | Send Apple Events (automation, scripting) |
| `com.apple.security.cs.allow-unsigned-executable-memory` | Required by libghostty (Zig/Metal GPU rendering) |
| `com.apple.security.cs.disable-library-validation` | Load the GhosttyKit framework |

The app does **not** use App Sandbox (`com.apple.security.app-sandbox` is absent) because Mori requires full access to the filesystem, tmux, and shell processes.

## 8. Troubleshooting

### "Developer ID Application" not available in Xcode

This certificate type can only be created through the [Apple Developer web portal](https://developer.apple.com/account/resources/certificates/add), not through Xcode's UI.

### `errSecInternalComponent` during signing

The keychain is locked or the certificate's private key is not accessible:

```bash
security unlock-keychain ~/Library/Keychains/login.keychain-db
```

### Notarization fails with "Invalid signature"

Ensure you're using `--options runtime` (hardened runtime). The `sign.sh` script does this automatically. If you signed manually, re-sign:

```bash
codesign --force --options runtime --timestamp \
  --entitlements Mori.entitlements \
  --sign "Developer ID Application: Your Name (ABC1234DEF)" \
  Mori.app
```

### Notarization fails with "The software is not signed with a valid Developer ID certificate"

Your certificate might be:
- Expired — check at [developer.apple.com/account/resources/certificates/list](https://developer.apple.com/account/resources/certificates/list)
- Revoked — create a new one following step 1
- Not a "Developer ID Application" cert — "Apple Development" or "Apple Distribution" won't work

### `spctl --assess` says "rejected"

The app isn't notarized or the staple is missing:

```bash
# Check if notarized
xcrun stapler validate Mori.app

# If not, re-notarize
SIGNING_IDENTITY="..." KEYCHAIN_PROFILE="mori-notarize" bash scripts/sign.sh --notarize
```

### Notarization takes too long

Apple's notary service usually responds within 5 minutes but can take up to an hour during peak times. The `--wait` flag in `sign.sh` polls automatically.

Check status of past submissions:

```bash
xcrun notarytool history --keychain-profile "mori-notarize"
xcrun notarytool log <submission-id> --keychain-profile "mori-notarize"
```
