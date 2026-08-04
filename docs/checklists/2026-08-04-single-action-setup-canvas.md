# Single-Action Windows Setup Canvas Checklist — 2026-08-04

## Presentation states

- [x] Needs-installer state emphasizes one download action.
- [x] Needs-preparation state identifies the selected ISO without exposing its path.
- [x] Ready-to-install state explains that Windows Setup opens inside Veil.
- [x] In-progress state replaces the primary button with stable progress feedback.
- [x] Needs-integration state keeps the existing app-connection action.
- [x] Ready state keeps the installed Windows app flow intact.
- [x] Failure state uses safe product copy and a usable recovery route.

## Interaction and accessibility

- [x] The setup canvas contains exactly one prominent action.
- [x] Use Existing ISO is directly discoverable only when installer access is needed.
- [x] Settings and Diagnostics use quiet controls with accessibility labels and help.
- [x] The state title is exposed as a semantic heading.
- [x] Progress exposes an accessibility value and prevents duplicate primary actions.
- [x] The regular installed-app window has no clipping or nested card frame.
- [x] The installed app remains usable at the current display's 900 x 620 dynamic minimum; the 820 x 560 limited-display policy passes its Swift test.
- [x] The default keyboard action and installed accessibility tree expose the primary and secondary controls.

## Automated verification

- [x] Presentation-model RED failure observed before implementation.
- [x] Lifecycle canvas-contract RED failure observed before implementation.
- [x] Focused Swift shell tests pass (23 tests).
- [x] macOS lifecycle source contracts pass (13 tests).
- [x] Full non-Windows-agent regression gate passes, including 25 Node test packages.

## Distribution safety

- [x] The application bundle builds and verifies.
- [x] Install and guarded replacement pass.
- [x] Uninstall preserves application-support data.
- [x] Reinstall and launch pass.
- [x] `/Applications/Veil.app` passes strict deep code-sign verification.
- [x] The existing Windows ISO remains 7,951,140,864 bytes with modification time 2026-08-03 21:57:17 +0900.
