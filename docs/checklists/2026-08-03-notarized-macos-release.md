# Notarized macOS Release Checklist

Date: 2026-08-03

Goal: prevent ad-hoc development bundles from being distributed and produce a Developer ID-signed, notarized Veil archive that Gatekeeper accepts on another Mac.

## Implemented gate

- [x] Keep local development signing in `script/build_and_run.sh` and label it non-distributable.
- [x] Use `VeilHostShell.release.entitlements` without `com.apple.security.get-task-allow`.
- [x] Require an exact `Developer ID Application:` identity with its private key.
- [x] Require a named `notarytool` Keychain profile without putting credentials in commands or reports.
- [x] Build the Swift package in release configuration.
- [x] Sign with hardened runtime and secure timestamps.
- [x] Submit a ZIP with `notarytool --wait` and require `Accepted`.
- [x] Staple and validate the ticket on `Veil.app`.
- [x] Run strict code-signature verification and `spctl` Gatekeeper assessment.
- [x] Rebuild the ZIP after stapling and write a credential-free SHA-256 release report.
- [x] Block dirty worktrees by default and clear only known files under `dist/release`.

## Verification still requiring release credentials

- [ ] Install a valid Developer ID Application certificate and private key in the release Keychain.
- [ ] Store a notarization credential profile with `xcrun notarytool store-credentials`.
- [ ] Run `./script/release_macos.sh --preflight` successfully from a clean tagged commit.
- [ ] Run `./script/release_macos.sh --notarize` and record Apple status `Accepted`.
- [ ] Download the resulting ZIP through the real distribution channel on a separate clean Mac.
- [ ] Confirm Gatekeeper opens Veil without “damaged” or unidentified-developer errors.

Until every credential-backed item passes, the top-level “no damaged warning on another Mac” feature remains incomplete.
