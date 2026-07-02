# QEMU Installer Boot Evidence Checklist

Goal: move from QEMU readiness into real Windows installer boot evidence.

- [x] Install local Homebrew QEMU on the test Mac.
- [x] Confirm `qemu-system-aarch64` is available.
- [x] Confirm Arm EDK2 firmware is available.
- [x] Confirm the downloaded Windows ISO contains `efi/boot/bootaa64.efi`.
- [x] Add Arm UEFI firmware to the QEMU boot plan.
- [x] Add ISO boot order, USB controller, `ramfb`, and lock-safe ISO drive options.
- [x] Validate QEMU can start the configured device graph without immediate argument failure.
- [x] Attempt real QEMU boot with the downloaded Windows 11 Arm ISO.
- [x] Record that the current QEMU path reaches Arm UEFI but does not yet reach Windows Setup.
- [x] Add repeatable QEMU launch records with process logs and a VM-console `screendump` screenshot path.
- [x] Extend bounded `qemu-smoke` runs to capture and validate VM-console screenshot paths.
- [x] Add recovery `nextActions` to QEMU smoke reports for common boot failures.
- [x] Convert QEMU monitor screenshots to PNG paths so visual evidence opens cleanly on macOS.
- [x] Read `qemu-launch-latest.json` into runtime snapshots and show the latest console PNG in the setup surface.
- [x] Send bounded boot-prompt key input during `qemu-smoke` and require `boot-prompt-key-sent` evidence for UEFI shell reports.
- [x] Prove a Windows Setup screen with the selected ISO and commit the working device recipe.
- [x] Advance past the product-key prompt without bundling a `ProductKey/Key` value.
- [x] Record the initial real Windows Setup blocker: Windows reported missing TPM 2.0 and Secure Boot support.
- [x] Install `swtpm`, attach QEMU `tpm-tis-device`, and record `tpm2-detected` smoke evidence.
- [x] Record the updated real Windows Setup blocker: Secure Boot is still required.
- [ ] Add a Secure Boot-capable AArch64 QEMU/HVF firmware and variable-store recipe.

Evidence: on July 2, 2026, `veil-vmctl qemu-smoke --json --seconds 25`
generated a console PNG showing the Korean Windows 11 Setup product-key screen
with the local `Win11_25H2_Korean_Arm64_v2.iso`. The JSON serial classifier was
`runningNoDecision`, so the console PNG is the proof for this checkpoint.

Follow-up evidence: after regenerating `Autounattend.xml` with
`ProductKey/WillShowUI=Never` and no `ProductKey/Key`, a July 2, 2026
`qemu-smoke --json --seconds 60` run generated a console PNG showing Windows 11
Setup's Korean requirements page for missing TPM 2.0 and Secure Boot support.

TPM evidence: after installing `swtpm` and attaching QEMU's TPM emulator, a
July 2, 2026 `qemu-smoke --json --seconds 120` run reported `tpm2-detected`.
The console PNG then showed only the Korean Secure Boot requirement failure.
