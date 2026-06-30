# VM Preflight Checks Checklist

Goal: reduce VM boot and install errors by validating profile settings before the Virtualization.framework boot path exists.

## Checklist

- [x] Add structured preflight checks to VM runtime snapshots.
- [x] Validate Windows Arm guest OS targeting.
- [x] Validate minimum CPU allocation.
- [x] Validate minimum memory allocation.
- [x] Validate minimum disk size.
- [x] Block boot readiness when preflight checks fail.
- [x] Show preflight checks in the SwiftUI VM Runtime panel.
- [x] Document the preflight criteria.
- [x] Run Swift and harness tests.
- [x] Commit and push to `main`.

## Out of Scope

- Measuring actual free disk space.
- Creating or resizing virtual disks.
- Building a `VZVirtualMachineConfiguration`.
- Running Windows.
