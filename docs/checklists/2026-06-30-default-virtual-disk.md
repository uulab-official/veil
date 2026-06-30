# Default Virtual Disk Checklist

Goal: let the host prepare a local blank Windows 11 Arm VM disk without bundling Windows media or claiming boot support.

## Checklist

- [x] Add a `VMRuntimeService` boundary for default disk creation.
- [x] Create a default sparse disk at `~/Virtual Machines/Veil/Windows 11 Arm.img`.
- [x] Persist the disk path back into the local VM profile.
- [x] Keep shared-folder preparation intact when disk creation creates the first profile.
- [x] Expose Create Disk controls in the VM Runtime screen.
- [x] Update README and legal/support wording.
- [x] Add tests for model handoff and local file creation.
- [x] Run Swift and harness verification.
- [x] Commit and push to `main`.

## Out of Scope

- Downloading or bundling Windows media.
- Installing or activating Windows.
- Validating installer contents.
- Booting a `VZVirtualMachine`.
