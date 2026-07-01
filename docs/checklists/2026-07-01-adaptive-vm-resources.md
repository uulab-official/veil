# Adaptive VM Resources Checklist

- [x] Add a deterministic `VMResourcePolicy` for host-sized default resources.
- [x] Keep the static Windows 11 Arm profile defaults stable for existing tests.
- [x] Let `LocalVMRuntimeService` apply the adaptive plan when creating or preparing a default VM.
- [x] Allow tests to inject a fixed resource plan.
- [x] Surface configured CPU, memory, and disk values in runtime snapshots.
- [x] Update the VM Runtime UI to show configured adaptive resource caps.
- [x] Document that this is a preparation/start-time cap, not live VM hot-resizing.
- [ ] Validate the adaptive profile against a real Windows 11 Arm installation.
- [ ] Add telemetry-driven recommendations after the guest agent is connected.
