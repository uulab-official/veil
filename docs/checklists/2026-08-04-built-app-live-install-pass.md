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

## QEMU/HVF follow-up — 2026-08-04

The display blocker above is resolved for the active compatibility provider. This follow-up used the official notarized UTM 4.7.5 app as an unprivileged QEMU framework source; no Windows image, UTM asset, or runtime binary was added to the repository.

- [x] Verified the downloaded UTM 4.7.5 DMG signature, notarization, bundle identity, and installed app signature before use.
- [x] Launched UTM's QEMU 10.0.2 and `swtpm` frameworks through a locally signed Veil runtime bridge under the user's Application Support folder.
- [x] Added `VEIL_SWTPM` support so the boot plan and prerequisite report resolve the same explicit TPM runtime as the app.
- [x] Confirmed `veil-vmctl providers --json` reports the local QEMU/HVF provider active and QEMU 10.0.2.
- [x] Confirmed `veil-vmctl qemu-doctor --json` reports the Windows 11 Arm plan ready with QEMU, secure UEFI, writable vars, TPM 2.0, HVF, installer media, support media, and sparse disk present.
- [x] Launched the built Veil app into one full-window Windows setup canvas with no nested setup window.
- [x] Confirmed the real Korean Windows 11 Arm installer reached 11%, then 25%, and entered its first restart phase.
- [x] Confirmed the app-owned QEMU and `swtpm` processes remained alive during installation and the loopback VNC console was capturable.
- [x] Added an embedded-display regression test proving an initial VNC connection refusal is retried instead of leaving the Windows canvas permanently stale.
- [x] Corrected installer boot order to `once=d,order=c`, so the ISO is preferred for the first setup boot and the partially installed system disk is preferred after Windows restarts.
- [x] Relaunched the rebuilt app against the partially installed disk and confirmed the active command uses `-boot order=c`, live VNC frames reconnect without a stale error banner, and system-disk I/O resumes.
- [x] Passed the full macOS host regression suite: 423 tests across 28 suites.
