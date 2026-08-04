# Native Full-Screen Windows Setup QA — 2026-08-04

## Behavior

- [x] Entering the Windows download route requests native macOS full screen.
- [x] Starting or resuming Windows requests native macOS full screen.
- [x] A window already in full screen is not toggled back to windowed mode.
- [x] The existing full-content route remains edge-to-edge below the app chrome.
- [x] Standard macOS full-screen controls remain available for exiting.

## Verification

- [x] Focused Swift tests pass.
- [x] macOS lifecycle harness passes.
- [x] Full regression gate passes.
- [x] Signed app is removed from and reinstalled to `/Applications/Veil.app`.
- [x] Live UI inspection confirms the app enters its own full-screen Space.
- [x] Back navigation removes only a new partial download and preserves the verified ISO.
