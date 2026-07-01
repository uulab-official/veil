# QEMU Doctor Readiness Checklist

Goal: add a UTM/Parallels-style readiness report for the local QEMU/HVF Windows Arm path.

- [x] Add Swift tests for QEMU doctor pass/fail checks.
- [x] Implement a typed `QEMUWindowsReadinessReport`.
- [x] Add `veil-vmctl qemu-doctor --json` for local readiness export.
- [x] Add a Node harness fixture and validator for doctor JSON.
- [x] Document the doctor command and next-action guidance.
- [x] Run Swift, Node harness, live doctor validation, and diff checks.
