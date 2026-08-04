# UI/UX Polish QA — 2026-08-04

## First Run

- [x] The hero explains the user outcome before VM implementation details.
- [x] Automatic download is the single prominent action.
- [x] Existing ISO selection remains visible as a secondary action.
- [x] Setup is explained as a short Get Windows → Install → Open Apps journey.
- [x] Licensing and local-storage expectations are visible without warning-heavy copy.

## Windows Download

- [x] Find, Download, Verify, and Prepare states have a stable progress layout.
- [x] Download percentage uses monospaced digits and an accessible progress value.
- [x] Microsoft source and local-save behavior remain visible.
- [x] Existing ISO and official Microsoft page remain directly accessible.
- [x] Back navigation remains available through the button and Escape shortcut.

## Verification

- [x] Focused Swift tests pass.
- [x] macOS lifecycle UI harness passes.
- [x] Full regression gate passes.
- [x] Signed app is installed to `/Applications/Veil.app`.
- [x] Live UI inspection covers first run, download, and back navigation.
- [x] Existing verified Windows ISO remains unchanged.
