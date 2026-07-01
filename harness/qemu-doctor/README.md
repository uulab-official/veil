# QEMU Doctor Harness

This harness validates `veil-vmctl qemu-doctor --json` output.

The doctor report is read-only. It checks whether the local Windows Arm QEMU/HVF path has a profile, installer ISO, writable system disk, QEMU executable, and HVF command plan. It never launches QEMU and never mutates VM files.

Run fixture tests:

```bash
npm test
```

Validate live host output:

```bash
cd ../../apps/mac-host
swift run veil-vmctl qemu-doctor --json | node ../../harness/qemu-doctor/src/validate-qemu-doctor.mjs
```

Expected output: `qemu doctor valid`.
