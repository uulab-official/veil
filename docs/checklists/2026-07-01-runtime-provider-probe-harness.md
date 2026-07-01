# Runtime Provider Probe Harness Checklist

Goal: make UTM-style local runtime provider readiness observable before real Windows installer work.

- [x] Add `VMRuntimeProviderProbe` with deterministic tests.
- [x] Detect `qemu-system-aarch64` through `VEIL_QEMU_SYSTEM_AARCH64` or common local install paths.
- [x] Report QEMU/HVF as `planned` when no local executable is found.
- [x] Include provider candidates in runtime snapshots and diagnostics.
- [x] Add `veil-vmctl providers --json`.
- [x] Add a Node harness that validates provider JSON output.
- [x] Add an Apple + QEMU provider fixture.
- [x] Document that the probe is read-only and serverless.

Next:

- [ ] Add a QEMU version probe once local QEMU execution is introduced.
- [ ] Add a provider decision matrix after real Windows ISO display testing.
