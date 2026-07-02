# QEMU Smoke Harness

This harness validates `veil-vmctl qemu-smoke --json` output.

The smoke command launches QEMU/HVF headlessly for a bounded time, uses snapshot mode, sends bounded boot-prompt key input through QEMU's monitor, writes serial/process logs plus a `qemu-smoke-*.console.png` VM-console screenshot path under `~/Downloads/Veil Diagnostics/QEMU Smoke`, and classifies the boot evidence with recovery `nextActions`. It is meant to prove whether the current recipe reaches Windows Setup, UEFI shell, or an earlier QEMU failure.

Run fixture tests:

```bash
npm test
```

Validate live host output:

```bash
cd ../../apps/mac-host
swift run veil-vmctl qemu-smoke --json --seconds 120 | node ../../harness/qemu-smoke/src/validate-qemu-smoke.mjs
```

Expected current output on the test Mac: `qemu smoke valid` with `outcome: "runningNoDecision"`, `boot-prompt-key-sent` evidence, a `consoleScreenshotPath` pointing at a `.png` image, and `nextActions` asking the contributor to inspect that screenshot. On July 2, 2026, the current secure-firmware, TPM, NVMe, and UEFI/GPT unattended recipe reached the Korean `Windows 11 installing` screen at 39% complete.
