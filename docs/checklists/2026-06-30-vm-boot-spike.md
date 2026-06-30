# VM Boot Spike Checklist

Goal: move Start from a placeholder boundary to a real Virtualization.framework boot attempt for user-provided Windows 11 Arm media.

## Checklist

- [x] Add a `VMRuntimeBooting` seam behind `LocalVMRuntimeService`.
- [x] Add tests proving boot-ready profiles call the boot runner.
- [x] Add tests proving incomplete profiles do not call the boot runner.
- [x] Build a `VZVirtualMachineConfiguration` with EFI, installer media, writable disk, NAT networking, keyboard, pointer, and graphics.
- [x] Persist EFI variables and generic machine identity next to the virtual disk.
- [x] Retain the active `VZVirtualMachine` for the process lifetime.
- [x] Open a `VZVirtualMachineView` console window after Start succeeds.
- [x] Sign the local app bundle with `com.apple.security.virtualization`.
- [x] Update docs and legal/support wording.
- [x] Run Swift, harness, bundle, and entitlement verification.
- [x] Commit and push to `main`.

## Out of Scope

- Downloading Windows media.
- Automating Windows setup.
- Installing the guest agent inside Windows.
- Proving every Windows 11 Arm installer variant boots.
- Seamless HWND mirroring.
