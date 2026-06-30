# VM Start Boundary Checklist

Goal: add a user-visible VM start request path without claiming that Veil can boot Windows yet.

## Checklist

- [x] Add `VMRuntimeService.start()` as the future boot integration point.
- [x] Add `VMRuntimeModel.start()` and tests for successful service handoff.
- [x] Add a local service error for the current boot-not-implemented state.
- [x] Show a Start VM control in the SwiftUI runtime panel.
- [x] Surface start errors while the runtime snapshot remains visible.
- [x] Document that Start currently exercises the boundary only.
- [x] Run Swift and harness tests.
- [x] Commit and push to `main`.

## Out of Scope

- Creating a `VZVirtualMachine`.
- Attaching disk, installer, network, or shared-folder devices.
- Persisting VM runtime process state.
- Starting Windows.
