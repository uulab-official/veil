# 8-Angle Review of the Swift Silent-Failure Fix (`692f6dd`)

Date: 2026-07-06

Goal: review `692f6dd` ("fix: stop silently dropping macOS host failures with
no log trace") with the same multi-angle process used on earlier commits
today, since it hadn't been reviewed yet.

## Findings Fixed

- [x] **Real bug: stale/unrelated `errorMessage` shown as this action's
      failure.** `HostDashboardModel.restoreMirroredWindowsAfterReconnect()`
      has two early-return `[]` paths (nothing to restore; no live agent
      connection) that never touched `errorMessage`. The new
      `VeilHostShellApp.restoreWindowsAppWindows()` code added in `692f6dd`
      reads `model.errorMessage` after an empty result and shows it as
      "Could not restore previous Windows apps: ..." — but if `errorMessage`
      was left over from a completely unrelated earlier failure (e.g. a
      failed app launch), and this call legitimately had nothing to restore,
      the user would see a misleading message blaming the wrong thing for a
      no-op. Fixed by clearing `errorMessage = nil` unconditionally at the
      top of `restoreMirroredWindowsAfterReconnect()`, matching the
      convention every other action in this file already follows. Covered by
      a new regression test (`clearsStaleErrorMessageWhenThereIsNothingToRestore`).
- [x] **Real privacy regression: all three new log lines used `privacy: .public`.**
      This is the exact bug class fixed hours earlier the same day in
      `exportDiagnostics` (`docs/checklists/2026-07-06-diagnostics-and-agent-visibility.md`):
      disk-read/write failures (boot report save, launch record load) and a
      guest-agent stream error commonly carry a full file path under the
      host user's home directory in their description. `.public` explicitly
      opts out of `os.Logger`'s default private redaction, meaning that path
      would appear unredacted in Console.app/`log stream`/sysdiagnose output
      — a channel `exportDiagnostics`'s redaction doesn't cover at all.
      Removed `privacy: .public` from all three call sites; default
      `.private` redaction now applies.
- [x] **Invented subsystem string didn't match the app's real bundle
      identifier.** `VeilLog`'s Logger subsystem was `"com.uulab.veil.host"`,
      but the actual shipped app's `CFBundleIdentifier`
      (`dist/Veil.app/Contents/Info.plist`) is `"org.uulab.veil.host-shell"`.
      Fixed so `log stream --predicate 'subsystem == "org.uulab.veil.host-shell"'`
      and Console.app filtering by the real bundle ID actually find these logs.
- [x] **Under-fixed: `stop()`'s corrupt-launch-record case only logged, it
      didn't close the orphan-process risk the commit message named.** The
      review found `QEMUVMRuntimeBooter.runningProcess(attachedToVirtualDiskPath:)`
      already exists and is already used elsewhere (boot-time orphan
      detection) to find a running QEMU process by virtual disk path,
      independent of the launch record file. Wired it in as a fallback: when
      the launch record is unreadable, `stop()` now also checks for an
      orphaned process by disk path and terminates it if found, instead of
      only logging that termination might not be possible.
- [x] **Unnecessary indirection: `saveBootReportLoggingFailure` was `static`
      and took `bootReportStore` as an explicit parameter** even though it's
      only called from instance methods where `bootReportStore` is already
      an instance property in scope. Made it an instance method; removed the
      parameter.

## Findings Noted as Follow-Ups, Not Fixed Now

- The `consumeProtocolMessages` retry loop (`VeilHostShellApp.swift`'s
  `startAgentEventPumpIfNeeded`) has no backoff, no retry cap, and no
  user-visible "reconnecting" state — a real guest-agent outage produces
  ~1800 silent retries/hour, now each logged, but still invisible in the UI.
  Fixing this is a product/UX decision (what should the user see while
  reconnecting?), not a mechanical silent-failure fix — out of scope for this
  pass.
- Two independently-invented, unlinked logging conventions now exist across
  the product: the Swift host's new `os.Logger`-based `VeilLog`, and the C#
  guest agent's plain `Console.Error.WriteLine` (from earlier today's
  `docs/checklists/2026-07-06-agent-silent-failure-audit.md`). Given the
  project's own diagnostics-bundle work cares about correlating host/guest
  failures for shared bug reports, a short doc note describing both
  conventions and how to correlate them during a live debugging session
  would help. Not written now — flagged for `docs/harness/README.md` or a
  new `docs/conventions/logging.md`.
- The eager `String(describing: error)` construction in all three new log
  calls happens in plain Swift before `Logger` ever sees it, which doesn't
  benefit from any interpolation-level laziness `os.Logger` might otherwise
  offer. Confirmed non-blocking (error `description` computation is cheap in
  practice, and no safe direct alternative was confirmed to compile without
  further research) — not changed.
- `loadSnapshot()` has a second, textually identical
  `try? await qemuLaunchRecordStore.loadLatest()` that this pass didn't
  touch (only `stop()`'s copy was fixed). Lower stakes there (display/read
  path, not a stop/terminate decision), but worth the same treatment in a
  future pass for consistency.

## Verification

- `swift build` and `swift test` — 238/238 pass (237 existing + 1 new
  regression test).
