# VM Status Panel Checklist

Goal: add the first VM runtime status boundary and show it in the SwiftUI host shell.

## Checklist

- [x] Add `VMRuntimeService` protocol.
- [x] Add `VMRuntimeSnapshot` value model.
- [x] Add `VMRuntimeModel` with loadable state and user-facing status text.
- [x] Add tests for supported host with no configured VM profile.
- [x] Add tests for unsupported host capability messaging.
- [x] Add `LocalVMRuntimeService` as the host-side capability probe.
- [x] Add a VM Runtime sidebar section.
- [x] Add a VM Runtime detail pane.
- [x] Document that this is a service boundary before actual VM boot.
- [x] Run Swift and harness tests.
- [x] Commit and push to `main`.

## Out of Scope

- Creating VM configuration.
- Booting Windows.
- Attaching disks or shared folders.
- Installing Windows or guest tools.
