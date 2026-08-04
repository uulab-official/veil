# Windows Settings UX Checklist — 2026-08-04

## Information architecture

- [x] Make Setup the default settings category.
- [x] Separate runtime controls from the installation assistant.
- [x] Separate macOS integration and readiness controls from runtime details.
- [x] Render only the selected category to reduce visual and accessibility-tree density.
- [x] Use a native segmented category picker with an accessibility label.
- [x] Keep the sheet-level Done action available from every category.

## Interaction verification

- [x] Open Windows Settings from the installed app.
- [x] Switch between Setup, Runtime, and Integration.
- [x] Confirm each category shows only its relevant controls.
- [x] Confirm Done closes the settings sheet.

## Automated verification

- [x] Add focused model coverage for settings categories.
- [x] Add lifecycle harness coverage for the categorized layout.
- [x] Run focused Swift tests (5 passed).
- [x] Run the macOS lifecycle harness (11 passed).
- [x] Run the full non-Windows-agent regression suite.

## Distribution safety

- [x] Build and verify the application bundle.
- [x] Replace-install `/Applications/Veil.app`.
- [x] Verify the installed app launches and exposes all categories.
- [x] Verify the downloaded Windows ISO remains unchanged (7,951,140,864 bytes).
