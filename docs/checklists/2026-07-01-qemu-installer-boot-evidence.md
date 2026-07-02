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
- [ ] Prove a Windows Setup screen with the selected ISO and commit the working device recipe.
