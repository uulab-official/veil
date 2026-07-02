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
- [x] Switch the Arm UEFI recipe from `-bios` to pflash code plus VM-local writable `uefi-vars.fd`.
- [x] Split Secure Boot firmware capability into its own doctor warning.
- [x] Discover and prefer a UTM-style `edk2-arm-secure-vars.fd` candidate when available.
- [x] Pad copied Arm UEFI variable stores to QEMU's 64 MiB pflash backend size.
- [x] Add `virtio-rng-pci` to the QEMU/HVF Windows 11 Arm device plan.
- [x] Record that secure vars plus RNG still do not satisfy Windows Setup Secure Boot on the current live smoke.
- [ ] Add a Secure Boot-capable AArch64 QEMU/HVF firmware and variable-store recipe that Windows Setup accepts.

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

Pflash evidence: after copying Homebrew QEMU's `edk2-arm-vars.fd` into the VM
directory as `uefi-vars.fd` and attaching Arm EDK2 through pflash drives, a
July 2, 2026 `qemu-smoke --json --seconds 120` run still reported
`boot-prompt-key-sent`, `tpm2-detected`, and `qemu-running`. The console PNG
still showed the Korean Secure Boot requirement failure, so the remaining
blocker is an AArch64 EDK2 build that advertises `secure-boot`.

Secure-vars candidate evidence: after inspecting UTM's QEMU resources, Veil now
discovers a local `edk2-arm-secure-vars.fd`, prefers it before generic
`edk2-arm-vars.fd`, upgrades pre-install `uefi-vars.fd` stores to that template,
and pads copied stores to 64 MiB. A July 2, 2026
`qemu-smoke --json --seconds 120` run with that secure vars candidate and
`virtio-rng-pci` still reported `boot-prompt-key-sent`, `tpm2-detected`, and
`qemu-running`; the console PNG still showed only the Korean Secure Boot
requirement failure. Veil therefore keeps Secure Boot as a doctor warning until
a live Windows Setup smoke proves the requirement is gone.
