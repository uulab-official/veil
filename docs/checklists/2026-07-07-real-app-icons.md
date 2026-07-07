# Real App Icons (v1.5 Plan Phase 2)

Date: 2026-07-07

Goal: replace the generic SF Symbol icons in the app catalog with each app's
real Windows icon, per Phase 2 of the approved v1.5 "Daily Use" plan
(`docs/roadmap.md`'s app-icons item). Previously `iconId` was a string that
existed since the first app catalog but was never resolved to a real image —
the shell just switched on the string to pick a generic SF Symbol.

## Implementation

- Guest (`apps/windows-agent/src/VeilAgent/WindowsAppIconExtractor.cs`, new):
  extracts each cataloged app's real icon via `Icon.ExtractAssociatedIcon`,
  encodes as base64 PNG, caches per executable since icons are static.
- Wired into `AgentSession.AppObject` so every `app.list.response` includes
  `iconPngBase64` per app (`null` on extraction failure or non-Windows).
- Protocol: added `iconPngBase64` to `app.list.response`'s per-app shape.
  Updated `docs/protocol.md` and
  `harness/protocol-fixtures/app.list.response.json` per AGENTS.md's
  "update protocol docs and fixtures whenever message shapes change."
- Host (`apps/mac-host/Sources/VeilHostCore/ProtocolMessages.swift`):
  `WindowsApp.iconPngBase64: String?` (defaulted `nil` for source
  compatibility with existing memberwise `init` call sites).
- Host UI (`apps/mac-host/Sources/VeilHostShell/Views/AppsView.swift`):
  `WindowsAppCard` decodes the base64 PNG into `NSImage` on demand and shows
  it in place of the SF Symbol, falling back to the SF Symbol only when no
  icon bytes were sent.
- Test coverage: `WindowsAppIconExtractorTests.cs` (extraction, PATH-based
  resolution, graceful-null, caching) and a new
  `HostDashboardModelTests.swift` case asserting a decoded icon reaches
  `model.apps` after `load()`.

## Real Bug Found During Live VM Verification

`ResolveExecutablePath` only checked the raw relative path and
`Environment.SpecialFolder.System` (System32). That covers `notepad.exe` and
`calc.exe`, but **`mspaint.exe` has no System32 entry on this Windows 11
build** — only an execution-alias stub under
`%LOCALAPPDATA%\Microsoft\WindowsApps`, which is on `PATH` but not in
System32 or the working directory. Confirmed live in the guest:

```
sys32exists=False resolved=C:\Users\veil\AppData\Local\Microsoft\WindowsApps\mspaint.exe
```

This is the same class of packaging quirk as the earlier `calc.exe` /
`CalculatorApp.exe` launch-matching fix from the prior session, but on the
icon-resolution path instead of window-matching.

### Fix

`ResolveExecutablePath` now also searches `PATH` (mirroring what
`Process.Start(UseShellExecute: true)` and `Get-Command` already do) before
falling back to the working directory. Added
`ExtractsAnIconForAnExecutableOnlyFoundViaPath` — copies a real exe into a
temp directory added to `PATH` under a unique name, so the test is
deterministic without depending on `mspaint.exe` actually being present on
the test machine (this test runs on macOS during regular `dotnet test`
cycles too, where it also verifies the guard behavior via the
`OperatingSystem.IsWindows()` early return).

## Verification

- `swift build` / `swift test`: 241/241 passing.
- `dotnet build` / `dotnet test` (`VeilAgent.Tests`): 15/15 passing.
- `harness/windows-agent-contract`: 18/18 passing (also fixed two assertions
  left stale by yesterday's `Find-VeilSharedAgentRoot` refactor, unrelated to
  this feature but discovered while re-running the suite here).
- `harness/fake-agent` (23/23), `harness/fake-host` (8/8), `packages/protocol`
  (17/17): all passing.
- Live VM (`veil-vmctl app-window-proof`, direct `app.list.request` over the
  WebSocket): confirmed real non-null `iconPngBase64` for all three catalog
  apps after the `PATH` fix —
  `winapp_notepad` (3584 bytes), `winapp_calculator` (820 bytes),
  `winapp_paint` (920 bytes) — and re-verified `app-window-proof` for
  Notepad still launches/tracks/frames correctly with the rebuilt agent.
