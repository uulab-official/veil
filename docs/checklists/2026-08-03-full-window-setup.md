# Full-Window Windows Setup QA — 2026-08-03

## Layout contract

- [x] Windows download is a main-content route, not a modal sheet.
- [x] The setup screen fills all available space below the app chrome.
- [x] The inactive blue setup canvas is not visible behind the download screen.
- [x] A labeled Back button returns to the setup overview.
- [x] Escape invokes the same safe Back action.
- [x] Settings remains a modal because it is secondary configuration.
- [x] Existing ISO selection returns to the main route before opening the system file picker.

## Verification

- [x] Focused Swift policy tests pass (24 tests).
- [x] macOS lifecycle harness passes (6 tests).
- [x] Full regression gate passes with the Windows agent explicitly skipped because .NET is unavailable (25 Node packages).
- [x] Signed app installs to `/Applications/Veil.app` and launches.
- [x] Live UI inspection confirms edge-to-edge setup content with no dimmed canvas or nested card.
- [x] Back and Escape cancel only an in-progress duplicate download and preserve the 7,951,140,864-byte verified ISO.
- [x] The final signed build was removed from and reinstalled to `/Applications/Veil.app`; the removed bundle remains recoverable in Trash.
