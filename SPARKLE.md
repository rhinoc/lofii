# Sparkle Auto-Update (Lofii)

Sparkle 2 is integrated in the app. `SUFeedURL`, `SUPublicEDKey`, and the version values live in `Sources/Lofii/Info.plist` and are embedded into the executable through the linker section. On release, GitHub Actions signs the zip with `sign_update` and inserts a new item into the repository-root `appcast.xml`.

## 1. Generate a Local EdDSA Key

Run this on a machine with the Sparkle distribution installed, including `generate_keys`:

```bash
# Generate and store the key in the local Keychain, or reuse an existing one.
/path/to/Sparkle-*/bin/generate_keys

# Print only the public key for Info.plist SUPublicEDKey.
/path/to/Sparkle-*/bin/generate_keys -p
```

Paste the printed **public key** into `Sources/Lofii/Info.plist` as `SUPublicEDKey`, replacing the placeholder `REPLACE_WITH_OUTPUT_OF_generate_keys`.

## 2. CI Private Key (GitHub Secret)

Export the private key from Keychain into a file. **Do not commit it.**

```bash
/path/to/Sparkle-*/bin/generate_keys -x ~/Desktop/sparkle_eddsa_private.txt
```

Create this secret in the GitHub repository under **Settings -> Secrets and variables -> Actions**:

- Name: `SPARKLE_ED_PRIVATE_KEY`
- Value: the **full file contents** of `sparkle_eddsa_private.txt`, usually a single Base64 line

The release workflow pipes this value into `sign_update --ed-key-file -`. If signing fails because the pasted value includes extra line breaks, store it as one line.

## 3. Appcast URL

By default, `SUFeedURL` points to `https://raw.githubusercontent.com/<your-repo>/main/appcast.xml`.
The first CI step rewrites `Sources/Lofii/Info.plist` using `github.repository`, so forks do not need manual edits.

Make sure **`appcast.xml` is available from the default branch through raw GitHub URLs**, which means merging the chore commit produced by the release workflow.

## 4. Distribution Format

The release artifact is **`lofii-<version>-macos.zip`**. It contains `lofii.app`, including the Live2D dylib, matching Sparkle's expected `.app` update format.

## 5. Optional: Match the Sparkle Tool Version

`scripts/update_appcast.sh` downloads `Sparkle-${SPARKLE_RELEASE_VERSION}.tar.xz` to use its `bin/sign_update`.
The default `2.9.1` matches the current SwiftPM-resolved Sparkle major version. If you upgrade Sparkle in `Package.swift`, set the workflow or local `SPARKLE_RELEASE_VERSION` environment variable to the same release.

## 6. Code Signing (Aligned With liltr)

The release workflow runs `scripts/code_sign.sh` before building. It imports the PKCS#12 certificate into a **temporary Keychain**, following the same approach as liltr. After `scripts/build_release.sh` assembles `Lofii.app`, `scripts/sign_built_app.sh` signs the frameworks, executable, and full bundle in order.

Configure these **Actions secrets** in the repository. The names can match liltr:

| Secret | Description |
|--------|-------------|
| `BUILD_CERTIFICATE_BASE64` | The exported `.p12` certificate as one Base64 block, matching the liltr CI format |
| `P12_PASSWORD` | Password for the `.p12` file |
| `KEYCHAIN_PASSWORD` | Temporary CI Keychain password; use any strong random string because it only lives inside the runner |

If all three values are **unset**, `code_sign.sh` skips the import and `sign_built_app.sh` applies an **ad-hoc** signature to the `.app`, close to the previous behavior and convenient for local or certificate-free CI builds.

- With an **Apple Development** identity: similar to liltr's default Xcode flow, suitable for development and internal testing; other machines may still require an "Open" confirmation.
- With a **Developer ID Application** identity: the script adds `--options runtime --timestamp`, ready for later `notarytool` notarization. The notarization step still needs to be wired into CI or run locally; the liltr scripts also do not currently perform notarization.
