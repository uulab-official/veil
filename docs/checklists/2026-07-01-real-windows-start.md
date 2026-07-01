# Real Windows Start Checklist

Goal: keep the main Veil experience pointed at real local Windows boot and console visibility, not a standalone demo flow.

## Completed

- [x] Recenter the main screen on one Windows 11 Arm machine instead of a multi-section sidebar.
- [x] Keep the default window large enough for a VM-focused control surface.
- [x] Ensure the primary ready-state action calls the real VM start path.
- [x] Open the VM Console through `VZVirtualMachineView` when a local display is available.
- [x] Rename visible progress from automatic-install simulation to VM console handoff.
- [x] Keep Windows media user-provided and local-only.
- [x] Confirm Apple Virtualization can start the configured VM and produce a `running` boot report.
- [x] Capture that the current Apple Virtualization console can still appear black even after VM start succeeds.
- [x] Add guarded `veil-vmctl qemu-start` execution for the local QEMU/HVF compatibility provider.
- [x] Verify `qemu-start` opens a visible foreground QEMU Cocoa window.
- [x] Record current QEMU/HVF result: TianoCore/Arm UEFI is visible, but Windows Setup is not reached yet.
- [x] Generate a local `Autounattend.xml` during VM preparation so automatic setup has a real artifact to attach next.
- [x] Generate and attach `VeilAutoInstall.iso` as setup-readable automatic install media in local runtime plans.

## Next

- [ ] Convert the console handoff timer into real `Virtualization.framework` state events.
- [ ] Verify boot with `/Users/bonjin/Downloads/Win11_25H2_Korean_Arm64_v2.iso` on the local Mac.
- [ ] Adjust the QEMU boot recipe so the Windows ISO reaches Windows Boot Manager instead of falling back to UEFI Shell.
- [ ] Add recovery copy for common boot failures: bad ISO attachment, unsupported device model, EFI state, and disk format issues.
- [ ] After Windows reaches the desktop, install and auto-start the Veil guest agent.
