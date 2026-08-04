# First-Run Journey UX Checklist — 2026-08-04

## Hierarchy and actions

- [x] Show the active setup stage above the first-run headline.
- [x] Distinguish completed, current, and upcoming journey stages.
- [x] Promote an existing ISO to a full secondary button.
- [x] Keep the download action visually primary.
- [x] Allow the action group to adapt to narrower window widths.
- [x] Surface Microsoft source, local execution, and license expectations together.

## Accessibility and behavior

- [x] Announce the state of each setup journey stage.
- [x] Preserve primary action labels and hints.
- [x] Give the existing ISO action an explicit accessibility label.
- [x] Verify the installed app exposes both actions and all trust items.
- [x] Verify Settings remains reachable from first run.

## Automated verification

- [x] Add focused setup-stage resolution coverage.
- [x] Extend the macOS lifecycle layout contract.
- [x] Run focused Swift tests (18 passed).
- [x] Run the macOS lifecycle harness (11 passed).
- [x] Run the full non-Windows-agent regression suite.

## Distribution safety

- [x] Build and verify the application bundle.
- [x] Replace-install `/Applications/Veil.app`.
- [x] Verify the final installed first-run screen visually.
- [x] Verify the downloaded Windows ISO remains unchanged (7,951,140,864 bytes).
