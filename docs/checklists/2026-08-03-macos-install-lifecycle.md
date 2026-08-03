# macOS Install Lifecycle Verification — 2026-08-03

Goal: verify Veil as an installed macOS app, not only as a development build, while preserving Windows media, VM disks, profiles, and diagnostics during uninstall.

- [x] Build and ad-hoc sign `Veil.app`.
- [x] Install the bundle at `/Applications/Veil.app`.
- [x] Verify the installed signature, bundle identifier, executable, and absence of quarantine metadata.
- [x] Launch the installed bundle and inspect the first-run window through macOS accessibility and a real screenshot.
- [x] Enter the automatic Microsoft download flow and verify that the latest Korean Arm64 ISO begins downloading.
- [x] Close the download sheet and verify that no partial ISO remains.
- [x] Quit the installed app and move only the verified app bundle to Trash.
- [x] Compare Application Support file hashes before and after uninstall; all existing files remained byte-identical.
- [x] Reinstall and relaunch the app from `/Applications`.
- [x] Add repeatable guarded install, uninstall, and lifecycle test scripts.
- [x] Verify replacement refuses a foreign bundle and leaves it unchanged.
- [x] Launch the isolated reinstalled bundle and enforce the branded first-window contract.
- [x] Add the lifecycle test to the repository-wide regression gate.
- [x] Give the first-run hero action an explicit accessibility label and hint.
- [x] Replace contradictory first-run provider copy with explicit compatibility-mode and app-window requirements.

Not exercised in this pass:

- A complete multi-gigabyte Windows ISO download and Windows installation were not repeated because that would create or modify licensed media and a user VM. The automatic Microsoft link acquisition, download start, cancellation, and partial-file cleanup paths were exercised against the live service.
- A notarized distribution install remains a release-signing gate; this pass validates the current ad-hoc development bundle lifecycle.
