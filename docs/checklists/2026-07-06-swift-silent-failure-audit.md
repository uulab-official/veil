# macOS Host Silent-Failure Audit

Date: 2026-07-06

Goal: after auditing and fixing the Windows agent (C#) for silent
background-task failures earlier the same day
(`docs/checklists/2026-07-06-agent-silent-failure-audit.md`), do the same pass
over the macOS host (Swift). Different shape of risk: SwiftUI `Task { }`
blocks in this codebase mostly call `async` (non-throwing) model methods that
already funnel errors into an `errorMessage`/`displayMessage` convention, so
the C#-style "uncaught exception kills a fire-and-forget task" bug class
mostly doesn't apply directly. The real gaps were in `try?` sites that
silently discard failures with **no logging at all** — this codebase had zero
logging framework anywhere in `Sources/` before this pass (no `os_log`,
`Logger`, or even `print`).

## Findings and Fixes

- [x] Added `VeilLogging.swift` (`VeilLog.runtime`, `VeilLog.agent` —
      `os.Logger` instances) since there was nothing to log to at all.
- [x] `HostDashboardModel.consumeProtocolMessages` caught every error from
      the guest-agent event stream and just `return`ed silently. Callers run
      this in a `while !Task.isCancelled` retry loop, so it self-heals, but a
      recurring failure (e.g. a real bug in `receiveProtocolMessage`) would
      have zero trace anywhere — window/clipboard sync would just stop with
      no explanation. Added a log line.
- [x] `VMRuntimeModel.start()`'s two `try? await bootReportStore.save(...)`
      calls (success and failure paths) silently dropped diagnostic-write
      failures. The boot itself still succeeds/fails normally, but the
      report other tooling depends on (`exportDiagnostics`, console-launch
      evidence in `loadSnapshot()`) would go silently stale. Replaced with a
      `saveBootReportLoggingFailure` helper that logs instead of discarding.
- [x] `VMRuntimeModel.stop()`'s `try? await qemuLaunchRecordStore.loadLatest()`
      collapsed two different situations into the same `nil`: "no launch
      record file exists" (legitimate, common) and "the file exists but is
      corrupt/unreadable" (a real failure). The second case matters here
      specifically because a `nil` launch record means `stopQEMULaunchIfRunning`
      can't identify the actual running QEMU process to terminate — a
      corrupt record could silently leave an orphaned QEMU process running
      after the user is told "Windows display closed." Split the two cases
      and log the throwing one.
- [x] `VeilHostShellApp.restoreWindowsAppWindows()` (the "Restore Previous
      Apps" action) had no failure path at all — every other action handler
      in the file sets `displayMessage` on both success and failure, this one
      set it on neither. If `restoreMirroredWindowsAfterReconnect()` came
      back empty because every restore attempt failed (rather than because
      there was genuinely nothing to restore), the user saw no windows
      reappear and no explanation why. Added a `displayMessage` update that
      checks `model.errorMessage` when the result is empty.

## Findings Noted as Follow-Ups, Not Fixed Now

- `HostDashboardModel.restoreMirroredWindowsAfterReconnect()`'s internal loop
  calls `launchApp(appId:)` per app, and each call resets `errorMessage = nil`
  before trying the next app — so only the *last* app's failure (if any)
  survives to the caller, and `restorableAppIds` isn't pruned on failure
  either. This session's fix (reading `model.errorMessage` after the loop)
  gives partial visibility (something failed) but not which app or how many.
  A proper fix would accumulate per-app failures into a list. Not done now —
  larger API-shape change than this pass's scope.
- `refreshRuntime()`, `refreshApps()`, and the "Refresh All" menu command in
  `VeilHostShellApp.swift` call `vmModel.load()`/`model.load()` (which set the
  models' own `errorMessage` on failure) without copying that into
  `displayMessage`, so a refresh failure is captured internally but not shown
  in the UI banner. Same class of gap as the fixed `restoreWindowsAppWindows`
  finding; not fixed now to keep this pass's diff focused on the highest-
  severity items (silent disk-write/read failures with no trace at all,
  versus a UI banner that's merely less complete than it could be).
- `VMRuntimeModel.swift`'s file-manifest enumeration `try?` chain and
  `HostDashboardModel.proofArtifacts(in:kind:)`'s `try?` on
  `contentsOfDirectory` were flagged as lower-severity: both treat "can't
  read" the same as "nothing there," which for `proofArtifacts` specifically
  means a permissions/IO error gets misreported to the user as "no proof has
  been saved yet" rather than "couldn't check." Not fixed now — genuinely
  best-effort display paths, lower stakes than the boot-report/launch-record
  findings above.

## Verification

- `swift build` and `swift test` — 237/237 pass, no regressions.
- No new unit tests added for the `VeilHostShellApp.swift` change
  (`restoreWindowsAppWindows`) — that file has no existing test coverage at
  this granularity (it's the SwiftUI App-layer entry point), consistent with
  the rest of the codebase's test boundaries. The model-layer logic it calls
  (`restoreMirroredWindowsAfterReconnect`) is already covered.
- The `os.Logger` calls themselves aren't asserted by a test (log capture
  wasn't worth the scaffolding for this pass) — verified by reading the code
  and confirming the log call sites are reachable exactly where the silently
  dropped errors used to be.
