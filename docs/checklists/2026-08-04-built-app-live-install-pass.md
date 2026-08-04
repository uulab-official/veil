# Built-App Live Windows Install Pass — 2026-08-04

Goal: exercise the packaged Veil app from first screen through a real Microsoft Windows 11 Arm64 download, verification, VM preparation, and local boot attempt without using the CLI as the product path.

## Environment

- Apple Silicon (`arm64`), macOS 26.5.1.
- Built app: `dist/Veil.app`, produced by `script/build_and_run.sh --verify-keep-running`.
- Active local provider at the start of the pass: Apple Virtualization.
- QEMU and `swtpm`: not installed.

## Completed live checks

- [x] Opened the packaged app into one full-window setup canvas with no nested setup window.
- [x] Confirmed the Diagnostics button opens Connection Check details instead of incorrectly opening Windows Settings.
- [x] Started the automatic Microsoft download, cancelled it, and confirmed that no partial ISO/download file remained.
- [x] Repeated the automatic flow and downloaded the current Korean Windows 11 25H2 Arm64 ISO directly from Microsoft.
- [x] Confirmed the completed file was saved only under Veil's local Application Support Downloads folder, never in the repository.
- [x] Confirmed the completed ISO size is `7,951,140,864` bytes.
- [x] Let the app complete its Microsoft-published SHA-256 verification before VM preparation became available.
- [x] Reviewed the contemporaneous Microsoft license prompt and continued only after explicit user confirmation.
- [x] Prepared a 128 GB sparse VM disk, EFI variable store, machine identifier, unattended setup media, and default VM profile.
- [x] Started and stopped the VM through the built app; the boot report recorded `result=succeeded` and `resultingState=running`.
- [x] Verified the ISO itself contains the Arm64 UEFI loader at `efi/boot/bootaa64.efi`.
- [x] Detached the diagnostic read-only ISO mount and stopped the VM after the pass.

## Defects found and corrected

### Diagnostics action routed to the wrong surface

When only a guest-agent connection diagnostic was available, the setup canvas showed Diagnostics but its click handler fell through to Windows Settings. `WindowsSetupDiagnosticsRoute` now resolves one source of truth for both visibility and action: exported diagnostics file, agent connection details, or unavailable.

### Pre-install runtime looked falsely complete

The header showed a green `Running` status and `Preparing Windows apps` while an uninstalled VM was only attempting Windows Setup. The status now remains a blue `Installing` state with `Windows Setup is running` until installation evidence exists.

## Live blocker

- [ ] The Windows Setup framebuffer did not become visible with the Apple Virtualization fallback.
  - The embedded canvas stayed black across a bounded wait, focus/key attempts, and one normal stop/restart cycle.
  - The VM process remained running and the boot report contained no startup error.
  - The sparse Windows disk remained at `0B` allocated, so this pass does not claim that setup progressed invisibly.
- [ ] The same built-app flow still needs to be repeated with the repository's proven QEMU/HVF provider.
  - The official Homebrew installer was attempted non-interactively.
  - Installation stopped before modifying `/opt/homebrew` because administrator authentication was unavailable.
  - No password or privilege bypass was attempted.

This result is consistent with the documented Windows installer display and device-driver risk of the Apple Virtio path. Veil must not treat a running VM state alone as proof that Windows is installed or that Windows apps are ready.

## Product boundary

Microsoft documents Windows 11 Arm64 ISOs as VM installation media and separately identifies Windows 365 and Parallels Desktop as its supported options for Windows 11 on Apple Silicon Macs. Veil remains an independent, unsupported open-source compatibility project and requires a separate valid Windows license.

Official references:

- https://learn.microsoft.com/en-us/windows/arm/iso
- https://support.microsoft.com/en-us/windows/experience/platform-variants/options-for-using-windows-11-with-mac-computers-with-apple-m1-m2-and-m3-chips
- https://developer.apple.com/documentation/virtualization
