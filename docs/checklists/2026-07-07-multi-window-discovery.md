# Multi-Window Discovery (v1.5 Plan Phase 3)

Date: 2026-07-07

Goal: report every top-level window belonging to an already-launched app, not
just the one window discovered at launch time, per Phase 3 of the approved
v1.5 "Daily Use" plan. Previously a second document window, a second
independently-launched instance of the same app, or a Save-As dialog were
invisible to the host — only the single window `LaunchAppAsync` happened to
find during its launch-time polling loop was ever tracked or reported.

## Implementation

- Guest (`apps/windows-agent/src/VeilAgent/WindowDiscoveryStreamer.cs`, new):
  a `PeriodicTimer`-driven background scan (2s interval), mirroring the
  existing `ClipboardTextStreamer`/`WindowFrameStreamer` pattern already used
  in this codebase. Each tick:
  1. Prunes windows the host was never told closed (see "Real Bug Found"
     below).
  2. Scans every app with at least one tracked window
     (`AgentSession.SnapshotTrackedAppsForDiscovery`) for windows not already
     known, via `WindowsDesktop.DiscoverAdditionalWindows` — an `EnumWindows`
     pass reusing the same `DoesProcessMatchApp` process-name matching
     `LaunchAppAsync` already uses, so it also catches a completely separate
     new process instance of the same app, not just a second window in the
     same process.
  3. Broadcasts `window.created` for each newly discovered window via
     `AgentSession.TryTrackDiscoveredWindow`, which re-checks under the
     tracking lock to guard against racing a concurrent launch/close for the
     same window id.
- `AgentSession` now tracks `appByWindowId` alongside the existing
  `trackedWindowsById`, so the discovery scan knows which app each tracked
  window belongs to.
- Wired into `WebSocketAgentServer`/`Program.cs` the same way
  `ClipboardTextStreamer` is: started once in `RunAsync`, broadcasting to all
  connected clients.
- **Host follow-up fixed later:** `mirrorSessions` were already keyed by
  `windowId`, but `WindowsAppWindowPresenter` still collapsed same-app
  windows through an `appId -> windowId` map. The presenter is now keyed by
  guest `windowId`/HWND only, so a `window.created` for a second window from
  the same app opens a second independent macOS mirror window while a refresh
  of the same `windowId` updates the existing host window.
- Design decision (flagged in the plan for confirmation): went with the
  recommended **continuous background scan** over an on-demand rescan
  message, for consistency with the existing clipboard/frame streamer
  pattern and to avoid a new protocol message for something with a steady,
  low, and already-precedented CPU cost.

## Real Bug Found During Code Review (fixed before live verification)

The 8-angle review caught a real gap in the first draft: there was no path
that noticed a window closing *directly on the guest* (user clicks the
window's own close button, Alt+F4, or the app exits) — only
`window.close.request` (host-initiated) ever called `UntrackWindow`. Two
consequences:

1. `trackedWindowsById`/`appByWindowId` would keep a stale entry forever,
   so the discovery scan would keep re-scanning a "tracked" app indefinitely
   even after every one of its windows closed.
2. Since `windowId` is derived purely from the HWND
   (`hwnd:{hwnd.ToInt64():X8}`) and Win32 reuses HWND values after a window
   is destroyed, a stale entry could make a **genuinely new** window that
   happens to reuse that HWND look "already known" and never get reported —
   a silent, hard-to-reproduce false negative.

### Fix

Added `WindowsDesktop.IsWindowStillOpen(windowId)` (parses the windowId back
to an HWND and calls `IsWindow`) and `AgentSession.TryUntrackClosedWindow`.
`WindowDiscoveryStreamer` now prunes every known window id whose
`IsWindowStillOpen` returns false *before* each discovery pass, broadcasting
`window.closed` for each one — this removes the stale entry before it could
ever mask a reused HWND. Also fixed two smaller review findings while in the
area: extracted a shared `FormatWindowId` helper (the windowId format was
independently duplicated in three places) and replaced a `Distinct()` +
per-app `Where()` re-scan (which leaned on `WindowsAppDescriptor` record
equality — safe today since `AppCatalog` entries are static singletons, but
a latent trap for any future per-launch-constructed descriptor) with a
single-pass `GroupBy`.

## Verification

- `swift build` / `swift test`: 241/241 passing (no Swift changes this
  phase; confirms nothing else regressed).
- `dotnet build` / `dotnet test` (`VeilAgent.Tests`): 20/20 passing, including
  new `WindowDiscoveryStreamerTests.cs` covering: broadcasting
  `window.created` for a newly discovered window, not re-announcing an
  already-tracked window, pruning-and-broadcasting `window.closed` for a
  window closed directly on the guest (the review-caught bug's regression
  test), and tolerating a transient per-tick discovery failure without
  killing the stream.
- `harness/windows-agent-contract`: 19/19 passing, extended with a new test
  asserting the `WindowDiscoveryStreamer`/`Program.cs`/`WebSocketAgentServer`
  wiring and the `IsWindowStillOpen`/`TryUntrackClosedWindow`/
  `PruneClosedWindowsAsync` shapes.
- Live VM (`veil-vmctl app-window-proof`, direct WebSocket automation):
  1. Launched Notepad via the normal `app.launch.request` path.
  2. Opened a **second, completely independent** `notepad.exe` instance
     directly via the Windows Run dialog — bypassing Veil's own launch flow
     entirely — and confirmed the periodic scan picked it up and broadcast
     `window.created` for `winapp_notepad` with no corresponding
     `app.launch.request` ever sent for it.
  3. Closed a window directly via its own title-bar close button (not
     `window.close.request`) and confirmed the pruning pass broadcast
     `window.closed` for it.
- Noted for the record: several live-VM attempts earlier in this session
  failed with connection timeouts / "did not return app.launch.response"
  after rapid repeated `qemu-install-agent` calls in quick succession —
  root-caused as the elevated repair flow's own process racing itself
  (`Stop-Process -Force` in `Repair-VeilAgentConnectivity.ps1` killing a
  just-restarted agent from an overlapping prior invocation), not a defect
  in this phase's code. A single clean `qemu-install-agent` call after a
  full VM reboot reproduced cleanly every time.
