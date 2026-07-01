# QEMU Boot Plan Harness

This harness validates `veil-vmctl qemu-plan --json` output.

The plan is intentionally a dry run. It describes the QEMU/HVF command Veil would need for a Windows 11 Arm install path, but the validator never launches QEMU and never touches the installer or disk.

Run fixture tests:

```bash
npm test
```

Validate live host output:

```bash
cd ../../apps/mac-host
swift run veil-vmctl qemu-plan --json | node ../../harness/qemu-boot-plan/src/validate-qemu-plan.mjs
```

Expected output: `qemu plan valid`.
