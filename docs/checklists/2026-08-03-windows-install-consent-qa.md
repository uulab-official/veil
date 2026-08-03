# Windows Install Consent QA — 2026-08-03

## Safety gate

- [x] A completed Microsoft ISO remains downloaded without preparing or starting a VM.
- [x] The download screen links to Microsoft's official license-terms page.
- [x] Downloaded ISO preparation requires an explicit `I Agree and Install Windows` action.
- [x] Existing ISO selection requires the same explicit confirmation.
- [x] Cancelling either confirmation does not call VM preparation or start.
- [x] Security-scoped access for a selected ISO is released after cancellation or preparation.

## Automated verification

- [x] Swift package tests pass (24 focused policy tests; full suite passed in regression gate).
- [x] macOS app lifecycle harness passes (5 tests).
- [x] Full regression gate passes with the Windows agent explicitly skipped because .NET is unavailable (25 Node packages).
- [x] App bundle builds, signs, installs, launches, uninstalls, and reinstalls in an isolated lifecycle environment.
- [x] The signed build was also removed from and reinstalled to `/Applications/Veil.app`; the removed bundle remains recoverable in Trash.

## Live first-run verification

- [x] Initial screen launches without a configured VM.
- [x] Settings opens and closes.
- [x] Microsoft page can be shown and hidden.
- [x] Latest Windows 11 25H2 Korean Arm64 ISO downloads directly from Microsoft.
- [x] The 7,951,140,864-byte ISO independently matches Microsoft's published Korean SHA-256 `723FDCB737B39A5EC1F4B0EADACF288F1A2C4C4C8C845EB1F6A433CC264BD426`.
- [x] Download completion stops at the license review screen.
- [x] License confirmation opens and `Not Now` returns to the verified ISO without preparing Windows.
- [x] Existing ISO picker cancellation leaves no profile, virtual disk, or VM process.
- [x] Quit and relaunch preserves the completed ISO in Application Support.

## Installation boundary

- [ ] Homebrew/QEMU runtime prerequisites are installed with user authorization.
- [ ] User explicitly accepts Microsoft license terms at the installation action.
- [ ] Windows Setup boots in the embedded VM display.
- [ ] Windows installation completes and survives app relaunch.
- [ ] VM/user data deletion is tested separately from app-bundle uninstall.

The final installation items require administrator authentication and the user's own Microsoft license acceptance. Codex must hand control back at those exact steps rather than entering credentials or accepting terms on the user's behalf.
