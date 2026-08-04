# Windows Download Screen UX Checklist — 2026-08-04

## Information hierarchy

- [x] Keep the automatic download as the primary screen.
- [x] Move the Microsoft web page toggle into an Options menu.
- [x] Preserve direct access to an existing ISO.
- [x] Show the current step number alongside the four-stage journey.
- [x] Keep percentage changes visually stable with numeric transitions.
- [x] Present Microsoft source, integrity verification, and local storage together.
- [x] Label the footer as automatic download instead of automatic setup.

## Accessibility and cancellation

- [x] Add an explicit accessibility label to Download Options.
- [x] Preserve per-stage accessibility status.
- [x] Preserve progress percentage accessibility values.
- [x] Verify Cancel returns to first run and removes the partial ISO.
- [x] Verify Options exposes the Microsoft page toggle.

## Automated verification

- [x] Extend the macOS lifecycle layout contract.
- [x] Run the focused Swift download tests (24 passed).
- [x] Run the macOS lifecycle harness (11 passed).
- [x] Run the full non-Windows-agent regression suite.

## Distribution safety

- [x] Build and verify the application bundle.
- [x] Replace-install `/Applications/Veil.app`.
- [x] Verify the installed download screen visually.
- [x] Verify the existing Windows ISO remains unchanged (7,951,140,864 bytes).
