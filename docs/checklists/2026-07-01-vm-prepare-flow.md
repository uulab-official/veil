# VM Prepare Flow Checklist

Goal: reduce the path from a fresh install to a boot attempt by creating the default profile, shared folder, and sparse disk in one host action.

## Checklist

- [x] Add `VMRuntimeService.prepareDefaultVM()`.
- [x] Add `VMRuntimeModel.prepareDefaultVM()`.
- [x] Create the default profile, shared folder, and sparse disk together.
- [x] Preserve an existing configured virtual disk path.
- [x] Add Prepare VM controls to the runtime screen.
- [x] Keep Profile Only available for low-level setup testing.
- [x] Update README, install flow, MVP, and roadmap docs.
- [x] Run Swift, harness, bundle, entitlement, and diff verification.
- [x] Commit and push to `main`.

## Out of Scope

- Downloading Windows installer media.
- Validating installer bootability.
- Automating Windows setup.
- Installing the guest agent.
