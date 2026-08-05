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

## Installed-desktop and guest-tools follow-up — 2026-08-04

- [x] Completed Windows OOBE with the local `Veil` account and reached the real Korean Windows 11 desktop.
- [x] Marked the profile installed only after desktop evidence existed; subsequent boots detach the Windows installer ISO and open the app-first Windows home.
- [x] Confirmed the installed desktop renders inside Veil's single full-window surface and the installed-state UI no longer covers the Windows taskbar with the setup control bar.
- [x] Measured the fallback guest framebuffer at `800×600`; this explains the remaining side margins and soft scaling before the Windows guest graphics driver is installed.
- [x] Kept `ramfb` as the safe fallback after a live boot without it correctly proved that unconfigured `virtio-gpu` reports `Display output is not active`.
- [x] Advertised the profile's `1440×900` target on `virtio-gpu-pci` for use once the guest graphics driver is active.
- [x] Corrected pointer mapping to use the aspect-fitted Windows image rectangle rather than the surrounding black letterbox.
- [x] Kept the last good RFB frame during transient reconnects, reset the retry budget after every live frame, hid reconnect noise after a valid frame, and stabilized SwiftUI image identity across frame and resolution changes.
- [x] Downloaded the official UTM Guest Tools `0.1.271` ISO from `getutm.app`, validated its ISO 9660 structure, recorded SHA-256 `65b6a69b392ee01dd314c10f3dad9ebbf9c4160be43f5f0dd6bb715944d9095b`, and attached it read-only.
- [x] Opened the guest-tools installer through QMP input and stopped at its explicit GPL/Windows-driver license agreement without accepting it automatically.
- [x] Added a one-confirmation future setup path: Veil automatically downloads and validates the official guest-tools ISO, mounts it from the first Windows boot, and schedules its silent first-logon installation before the Veil guest agent.
- [x] Passed the updated macOS host suite: 429 tests across 28 suites.
- [x] Passed `script/test_all.sh`, including the .NET 8 Windows agent, all 25 Node harness packages, signed app launch, and isolated install → guarded replace → uninstall → support-data preservation → reinstall lifecycle checks.
- [ ] Re-run a clean install to prove the newly merged one-confirmation guest-tools path end to end.
- [ ] Install the guest graphics tools on the current VM after explicit license acceptance, reboot, and confirm the VNC framebuffer changes from `800×600` toward the advertised `1440×900` target.

## One-click installed-VM optimization follow-up — 2026-08-05

The current installed Windows disk was preserved. This pass added and verified the app path that prepares integration media, performs a normal Windows restart, installs official UTM Guest Tools plus the Veil guest agent, waits for the agent to reconnect, and classifies the resulting framebuffer size.

- [x] Added the generated, idempotent `Optimize.cmd` media entrypoint without disk partitioning, formatting, installer replacement, or product-key handling.
- [x] Added bounded QMP automation for a normal ACPI shutdown, media rebuild, Windows startup, Run dialog dispatch, UAC confirmation, agent reconnect wait, and retryable failures.
- [x] Added one installed-Windows card with `Optimize Windows`, determinate stage progress, pre-dispatch cancel, and same-card retry instead of competing repair actions.
- [x] Added one combined confirmation describing official UTM Guest Tools, the Veil guest agent, one restart, preserved Windows files, and links to both terms/information pages.
- [x] Added live RFB dimension feedback; dimensions above `800×600` mark display optimization complete, while agent-only success remains visibly partial.
- [x] Corrected Finder-launched runtime discovery so the app automatically finds Veil's existing QEMU and `swtpm` bridges under `~/Library/Application Support/Veil/Runtime/bin` without shell environment variables.
- [x] Passed the affected VM profile (57), QEMU prerequisite (4), and QEMU boot-plan (62) suites, then passed the complete updated Swift suite: 451 tests across 29 suites.
- [x] Passed `script/test_all.sh`: Windows agent tests, all 25 Node packages, signed app launch, and isolated install → replace → uninstall → support-data preservation → reinstall lifecycle checks.
- [x] Rebuilt, installed, and signature-verified `/Applications/Veil.app`; confirmed the installed process is live and the real profile now shows the single `Finish Windows Optimization` card.
- [x] Opened the combined confirmation in the installed app and confirmed `Review Both Terms`, `I Agree and Optimize`, and `Not Now` are available.
- [x] Made the installed app offer the same confirmation automatically on the first app-home load when QEMU Windows lacks healthy integration, while suppressing duplicate prompts after a user defers it during the session.
- [x] Added RFB DesktopSize handling and resize-only frame retention so a live guest resolution change does not reconnect the stream or flash a black frame; the current fallback `1024×768` desktop remains stable until guest display tools are installed.
- [x] Rebuilt and reinstalled the packaged app after the automatic-offer change; the first-screen live check opened the combined confirmation without a manual card click.
- [x] Passed the complete updated Swift suite: 463 tests across 29 suites.
- [ ] Accept the terms in person, then observe the real current VM through media preparation, normal restart, installer dispatch, guest restart, agent reconnect, and post-reboot framebuffer dimensions. No end-to-end completion claim is made before those live observations occur.
