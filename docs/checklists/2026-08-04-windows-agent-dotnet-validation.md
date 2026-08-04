# Windows Agent .NET Validation Evidence

Date: 2026-08-04

Scope: close the previously unexecuted Windows-agent automated test gate on Apple Silicon without claiming a live Windows guest result.

## Environment

- [x] Installed the official .NET SDK 8.0.423 Arm64 with Microsoft's `dotnet-install.sh` into an isolated temporary directory.
- [x] Kept the repository and system-wide SDK state unchanged.
- [x] Used the project's `net8.0-windows10.0.19041.0` target with `EnableWindowsTargeting=true`.

## Verification

- [x] Command: `dotnet test apps/windows-agent/tests/VeilAgent.Tests/VeilAgent.Tests.csproj --configuration Release --logger 'console;verbosity=minimal'`
- [x] Restore: all projects up to date.
- [x] Build: `VeilAgent.dll` and `VeilAgent.Tests.dll` compiled in Release configuration.
- [x] Runner: VSTest 17.11.1 Arm64.
- [x] Result: 72 passed, 0 failed, 0 skipped; exit 0.
- [x] Operation ACK coverage includes request/operation correlation, successful mouse/key/clipboard/frame-control acknowledgement, silent legacy and mouse-move behavior, and mouse/key rejection errors.

## Regression coverage

- [x] Protocol validator: 30 passed, 0 failed.
- [x] Fake agent: 31 passed, 0 failed after restoring its pinned dependencies in the clean worktree.
- [x] Fake host: 8 passed, 0 failed after restoring its pinned dependencies in the clean worktree.
- [x] macOS host: 419 tests in 27 suites passed.
- [x] `./script/build_and_run.sh --verify` completed the app bundle build, ad-hoc signing, launch-report contract verification, and cleanup.

## Evidence boundary

- [x] This closes the automated Windows-agent `dotnet test` gate.
- [x] This closes the automated proof that mouse/key desktop `false` returns become structured protocol errors.
- [ ] This does not prove Windows-native input APIs, frame capture, transport, or the end-to-end Notepad loop inside a live Windows VM.
