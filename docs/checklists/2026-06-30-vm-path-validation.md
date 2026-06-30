# VM Path Validation Checklist

Goal: keep VM profile boot readiness tied to actual local files, not only stored path strings.

## Checklist

- [x] Add failing tests for missing installer media and virtual disk paths.
- [x] Add failing tests for directory paths where files are required.
- [x] Keep profiles with real local files boot-ready.
- [x] Return user-visible detail messages when stored paths are invalid.
- [x] Document the boundary between local file checks and Windows media validation.
- [x] Run Swift and harness tests.
- [x] Commit and push to `main`.

## Out of Scope

- Validating Windows installer contents.
- Creating virtual disk images.
- Security-scoped bookmark persistence.
- Booting or configuring a real VM.
