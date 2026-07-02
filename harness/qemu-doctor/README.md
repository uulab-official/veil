# QEMU Doctor Harness

This harness validates `veil-vmctl qemu-doctor --json` output.

The doctor report is read-only. It checks whether the local Windows Arm QEMU/HVF path has a profile, installer ISO, generated automatic install media, writable system disk, QEMU executable, Arm UEFI pflash firmware plus VM-local writable vars, Secure Boot candidate status, `swtpm` TPM 2.0 emulator, and HVF command plan. It never launches QEMU and never mutates VM files. Secure Boot candidate status requires the UTM-style `edk2-aarch64-secure-code.fd` plus `edk2-arm-secure-vars.fd` pair, and is still reported as a warning until a bounded live Windows Setup smoke proves that the requirement page is gone.

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
