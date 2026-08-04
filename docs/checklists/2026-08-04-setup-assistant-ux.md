# Setup Assistant UX Checklist — 2026-08-04

## Language and hierarchy

- [x] Replace VM-facing setup labels with Windows-facing language.
- [x] Highlight the first incomplete setup item as Next.
- [x] Distinguish complete, current, and pending setup rows.
- [x] Resolve one contextual primary action from setup state.
- [x] Remove disabled Installer and Disk buttons before a profile exists.
- [x] Move profile-only creation into Advanced setup options.
- [x] Keep existing ISO and disk selection available when relevant.

## Accessibility and behavior

- [x] Announce setup row state together with its title and detail.
- [x] Give Advanced setup options an explicit accessibility label.
- [x] Verify the installed Setup tab shows one primary action.
- [x] Verify Advanced exposes Create Profile Only.
- [x] Verify Done closes Windows Settings.

## Automated verification

- [x] Add focused primary-action resolution coverage.
- [x] Extend the macOS lifecycle layout contract.
- [x] Run focused Swift settings tests (6 passed).
- [x] Run the macOS lifecycle harness (12 passed).
- [x] Run the full non-Windows-agent regression suite.

## Distribution safety

- [x] Build and verify the application bundle.
- [x] Replace-install `/Applications/Veil.app`.
- [x] Verify the installed Setup tab visually.
- [x] Verify the downloaded Windows ISO remains unchanged (7,951,140,864 bytes).
