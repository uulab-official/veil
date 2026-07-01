# QEMU Boot Plan Harness Checklist

Goal: expose a deterministic QEMU/HVF Windows Arm boot plan without launching or mutating a VM.

- [x] Add Swift tests for a Windows 11 Arm QEMU/HVF install plan.
- [x] Implement a typed `QEMUWindowsBootPlanner` in host core.
- [x] Add `veil-vmctl qemu-plan --json` for read-only plan export.
- [x] Add a Node harness that validates QEMU plan JSON.
- [x] Add a fixture covering installer media, system disk, HVF, NAT, display, and input devices.
- [x] Document the plan command and its non-execution boundary.
- [x] Run Swift, Node harness, live plan validation, and diff checks.
