# UI/UX Refinement QA — 2026-08-04

## First Run

- [x] The setup hero has no duplicated bottom status bar before work begins.
- [x] Settings remain discoverable from a compact top-right control.
- [x] Settings opens and closes without changing the first-run route.
- [x] The primary setup action remains visually dominant.
- [x] Runtime controls return automatically when setup or Windows becomes actionable.

## Download and Recovery

- [x] Download stage changes animate without changing the overall layout.
- [x] Active downloads expose an explicit Cancel action.
- [x] Download failures expose Try Download Again and Use Existing ISO.
- [x] VM preparation failures expose Try Preparing Again and Choose Another ISO.
- [x] Escape and Back still leave the download route and remove partial media.

## Verification

- [x] Focused Swift tests pass.
- [x] macOS lifecycle UI harness passes.
- [x] Full regression gate passes.
- [x] Signed app is installed to `/Applications/Veil.app`.
- [x] Live UI inspection covers first run, cancel, and back navigation.
- [x] Existing verified Windows ISO remains unchanged.
