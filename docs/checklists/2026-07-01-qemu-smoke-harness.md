# QEMU Smoke Harness Checklist

Goal: make real QEMU boot attempts repeatable and machine-readable.

- [x] Add smoke report classification tests for UEFI shell fallback.
- [x] Add smoke report classification tests for QEMU argument failures.
- [x] Add headless smoke argument generation with snapshot mode and serial logging.
- [x] Add `veil-vmctl qemu-smoke --json --seconds N`.
- [x] Run a live bounded QEMU smoke test.
- [x] Add a Node harness for smoke report JSON.
- [x] Run full Swift, Node, live JSON, and diff checks.
