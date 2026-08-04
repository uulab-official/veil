# Window Header UX Checklist — 2026-08-04

## Status clarity

- [x] Replace the ambiguous Setup badge with Setup Required.
- [x] Distinguish checking, setup, ready, opening, running, paused, and failure states.
- [x] Give a live app connection precedence with Apps Ready.
- [x] Use semantic blue, green, and orange status tones.
- [x] Add product-facing subtitles for paused, failed, and unsupported states.

## Refresh feedback

- [x] Replace the refresh glyph with a progress indicator while checking.
- [x] Disable duplicate refresh actions while a refresh is active.
- [x] Add dynamic help, accessibility label, and accessibility value.
- [x] Animate header status changes without changing header height.
- [x] Verify the installed refresh control completes and returns to Ready.

## Automated verification

- [x] Add focused header-state resolution tests.
- [x] Extend the macOS lifecycle header contract.
- [x] Run focused Swift shell tests (19 passed).
- [x] Run the macOS lifecycle harness (13 passed).
- [x] Run the full non-Windows-agent regression suite.

## Distribution safety

- [x] Build and verify the application bundle.
- [x] Replace-install `/Applications/Veil.app`.
- [x] Verify the installed header visually.
- [x] Verify the downloaded Windows ISO remains unchanged (7,951,140,864 bytes).
