# First-Run Deep QA — 2026-08-03

Goal: exercise the installed first-run UI beyond the one-window launch contract and lock the damaged-app prevention path into repeatable automation.

## Installed UI exercise

- [x] Launch `/Applications/Veil.app` from a stopped state.
- [x] Confirm one branded `Veil` main window and no duplicate utility window.
- [x] Confirm the primary action is exposed to accessibility as `Download Windows 11`.
- [x] Refresh the unconfigured runtime and return to the same actionable state.
- [x] Open Windows Settings, inspect the install assistant and provider states, and close back to the launcher.
- [x] Open the Windows download sheet and reach Microsoft's current Windows 11 Arm64 page.
- [x] Confirm Microsoft exposes Windows 11 25H2 and a Korean Arm64 ISO link.
- [x] Show and hide the embedded Microsoft page without losing download progress.
- [x] Switch from an active automatic download to the existing-ISO picker.
- [x] Cancel the file picker and return to the launcher without creating a profile.
- [x] Confirm no `.iso`, `.download`, or `.part` file remains after cancellation.
- [x] Quit the app completely and relaunch the installed bundle into the same first-run state.

## Install lifecycle hardening

- [x] Copy a valid signed build and attach `com.apple.quarantine` to simulate a downloaded development bundle.
- [x] Install that quarantined source through `install_macos.sh`.
- [x] Confirm the installed copy has no quarantine metadata and still passes strict signature verification.
- [x] Run uninstall twice and confirm the second call is a successful no-op.
- [x] Preserve the existing foreign-bundle refusal, user-data sentinel, reinstall, and first-window checks.

## Boundaries

- Windows itself was not installed in this pass. Read-only diagnosis reports no VM profile, Windows ISO, QEMU, `swtpm`, or prepared VM disk on this Mac.
- The live Microsoft flow was stopped after download-path verification so the QA pass did not retain a multi-gigabyte licensed ISO.
- Developer ID notarization and clean-Mac Gatekeeper acceptance remain release-credential gates; this pass verifies the current ad-hoc local development lifecycle.
