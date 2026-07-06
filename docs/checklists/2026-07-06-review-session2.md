# 8-Angle Review of the Mutex-Fix / Calculator / Silent-Failure Commits

Date: 2026-07-06

Goal: review the six commits made after the diagnostics/agent-visibility pass
(`8cda82e` through `0cd675e`) with the same 8-angle multi-agent process used
earlier the same day, since they hadn't been through it yet.

## Findings Fixed

- [x] **`Repair-VeilAgentConnectivity.ps1`'s new self-copy guard only covered
      `Sync-VeilInstalledAppBundle`, not `Sync-VeilInstalledSupportScripts`.**
      Once installed, a repair run with no app bundle on any drive but stale
      support scripts already installed could hit the exact bug this file was
      supposed to fix — just for scripts instead of the app bundle — while
      still logging "Refreshed installed support script" as if it worked.
      Added the same resolved-path equality guard to
      `Sync-VeilInstalledSupportScripts`.
- [x] **`Find-VeilSharedAgentRoot`'s self-copy check compared a `Resolve-Path`
      result against the raw, un-normalized `$InstallRoot` parameter.** If
      `$InstallRoot` was ever passed (or defaulted) with a trailing separator
      or a non-canonical form, the `-ne` comparison could stay true even for
      the drive holding the actual install folder, silently reintroducing the
      self-copy bug. Normalized `$InstallRoot` once via
      `[System.IO.Path]::GetFullPath(...).TrimEnd('\')` right after the
      `param()` block (using `GetFullPath` instead of `Resolve-Path` since
      the install directory doesn't have to exist yet on a fresh install), so
      every later comparison is against the same canonical form
      `Resolve-Path` produces.
- [x] **A disconnected/stale drive could abort the whole repair run.** The
      script sets `$ErrorActionPreference = "Stop"` globally, and
      `Test-Path`/`Resolve-Path` against an unreachable network drive or
      stale substituted drive letter can throw instead of returning `$false`.
      Wrapped the per-candidate check in `Find-VeilSharedAgentRoot` in
      try/catch so one bad drive is skipped (with a log line) instead of
      failing the entire repair flow with an opaque error.
- [x] **`Find-VeilSharedAgentRoot` was re-scanning every attached drive twice
      per repair run** (once from each sync function) for a value that
      cannot change within one run. Cached the result in
      `$script:CachedSharedAgentRoot`, computed once.

## Findings Noted as Follow-Ups, Not Fixed Now

- The drive-scan heuristic itself (assume exactly one drive has a folder
  named literally `Veil Guest Agent`) is a reasonable match for the existing
  `Install-VeilVirtIONetworkDriver` pattern in the same file, but a more
  durable fix would have `Install-VeilAgent.ps1` persist the resolved source
  path to a marker file under `$InstallRoot` at install time, with the drive
  scan only as a fallback. Not done now — bigger scope than this pass, and
  the scan-based fix already closes the concrete bug that was found live.
- Three now-near-identical `catch (Exception error) { Console.Error.WriteLine(...) }`
  blocks were added across `WebSocketAgentServer.cs` in the previous commit,
  joining the pre-existing ones in `ClipboardTextStreamer.cs`/
  `WindowFrameStreamer.cs`/`AgentSession.cs` (6 total now). Worth extracting
  a shared logging helper before a 7th appears; not done now since it's pure
  duplication cleanup with no behavior change.
- `WindowsDesktop.DoesProcessMatchApp`'s LINQ chain (`Append`/`Select`/`Any`)
  allocates iterators on every call, and is called once per visible window
  per 100ms poll tick — confirmed not a real perf problem at current window
  counts and timeout budgets (worst case low thousands of small allocations
  over one Calculator launch), but a plain loop would read more clearly.
      Not changed — readability nit, not a bug.
- `WindowsAppDescriptor`'s `WindowDiscoveryTimeoutOverride` (ctor param) vs
  `WindowDiscoveryTimeout` (computed property) two-name indirection was
  flagged as a future-confusion risk if a caller ever reads the raw
  `...Override` field directly instead of going through the property. Not
  changed — no current caller does this, and collapsing it into one
  non-nullable property with a named default constant is a valid follow-up
  but not urgent.

## Findings Checked and Confirmed Not Bugs

- Discovery-attempt count via `WindowDiscoveryTimeout.TotalMilliseconds / 100`
  produces exactly 50 for the default 5s and 120 for Calculator's 12s — no
  truncation shortfall for any current descriptor (only a latent risk for a
  future non-multiple-of-100ms override).
- The duplicate `New-Item` removed from `Sync-VeilInstalledAppBundle` really
  was redundant; nothing between the surviving call and the later
  `Remove-Item` can delete the directory in between.
- `WebSocketAgentServer`'s `HandleClientAsync`/`HandleClientCoreAsync` split
  preserves the original `using(client)`/`clients.TryRemove` cleanup on every
  exception path via normal .NET stack-unwind semantics.
- `ClipboardTextStreamer`'s new catch filter (`when (error is not
  OperationCanceledException)`) correctly lets cancellation still propagate
  and exit the loop; `continue` only skips the rest of one tick.
- No call site of `WindowsAppDescriptor` uses positional arguments that could
  silently bind to the two new optional parameters; all use named arguments.
- `SingleInstanceGuard.Dispose()`'s catch of `ApplicationException` matches
  the exact, narrow, documented .NET behavior for this call
  (`Mutex.ReleaseMutex` throws `ApplicationException` specifically when the
  releasing thread doesn't own the mutex) — not overly broad in practice.
- No CLAUDE.md/AGENTS.md rule violations found (host/guest boundary,
  protocol-doc sync, clipboard-surprise, licensing-claims all checked and
  clear — the clipboard change actually reduces surprise rather than adding
  one).

## Verification

- `dotnet test apps/windows-agent/tests/VeilAgent.Tests` — 11/11 pass
  (unchanged by this pass; only the PowerShell script was touched).
- `Repair-VeilAgentConnectivity.ps1` still could not be syntax-checked with a
  real PowerShell parser in this sandbox (no `pwsh`, and installing it via
  `brew install --cask` requires an interactive `sudo` this sandbox doesn't
  have). Reviewed carefully by eye a second time; verify with `pwsh -File`
  or on a real Windows box before relying on it further.
