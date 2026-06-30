# VM Profile Paths Checklist

Goal: add installer media and virtual disk paths to VM profiles so the runtime can distinguish "profile exists" from "ready to boot".

## Checklist

- [x] Add optional installer media path to `VMProfile`.
- [x] Add optional virtual disk path to `VMProfile`.
- [x] Preserve both paths through JSON save/load.
- [x] Add path fields and boot readiness to `VMRuntimeSnapshot`.
- [x] Make `VMRuntimeModel.canStart` require boot readiness.
- [x] Add service/model method to update profile paths.
- [x] Add SwiftUI controls to select installer media and virtual disk path.
- [x] Document that paths reference user-provided local files.
- [x] Run Swift and harness tests.
- [x] Commit and push to `main`.

## Out of Scope

- Validating Windows media contents.
- Creating a virtual disk image.
- Booting a VM.
- Sandboxed bookmark persistence.
