# VM Profile Store Checklist

Goal: add a persisted local VM profile model so the VM Runtime panel can move from "not configured" to a startable stopped profile without booting Windows yet.

## Checklist

- [x] Add `VMProfile` value model.
- [x] Add `VMProfileStore` protocol.
- [x] Add JSON file-backed profile store.
- [x] Add tests for saving and loading a profile.
- [x] Add default Windows 11 Arm profile creation.
- [x] Make `LocalVMRuntimeService` report `.stopped` when a profile exists.
- [x] Add `VMRuntimeModel.createDefaultProfile()`.
- [x] Add a SwiftUI action for creating the default profile.
- [x] Document that the profile is configuration-only and does not include Windows media.
- [x] Run Swift and harness tests.
- [x] Commit and push to `main`.

## Out of Scope

- Creating virtual disks.
- Downloading or bundling Windows media.
- Booting the VM.
- Editing advanced CPU/RAM/disk settings in UI.
