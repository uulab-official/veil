# QEMU Provider Version Probe Checklist

Goal: make detected QEMU/HVF providers more actionable by reporting version metadata in diagnostics and harness output.

- [x] Add a deterministic Swift test for QEMU version metadata.
- [x] Extend `VMRuntimeProviderSummary` with optional executable version text.
- [x] Parse QEMU version output through an injectable probe closure.
- [x] Include version metadata in `veil-vmctl providers --json`.
- [x] Update the runtime-provider-probe harness fixture and validation.
- [x] Document the version probe and install guidance.
- [x] Run Swift, protocol, fake-agent, fake-host, runtime-provider-probe, live provider validation, and diff checks.
