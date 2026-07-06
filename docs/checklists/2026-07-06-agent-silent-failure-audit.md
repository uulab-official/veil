# Windows Agent Silent-Failure Audit

Date: 2026-07-06

Goal: after spending most of the day tracking down a guest-agent crash that
was hard to diagnose specifically because its real exception got masked by a
second exception thrown during cleanup
(`docs/checklists/2026-07-06-guest-agent-mutex-crash-fix.md`), audit the rest
of the Windows agent for the same class of bug: exceptions that silently kill
a background loop or fire-and-forget task with no diagnostic trace anywhere.

## Findings and Fixes

- [x] `ClipboardTextStreamer.StreamAsync` let any exception from
      `desktop.GetClipboardTextAsync` (e.g. a transient `OpenClipboard`
      failure — Windows clipboard access is contended by design, any app can
      briefly hold it) propagate out of the loop, permanently killing
      clipboard sync for the rest of the agent process's lifetime with no log
      line anywhere. `WindowFrameStreamer` already had the right pattern for
      this (catch per-tick, log, fall back, keep streaming) — brought
      `ClipboardTextStreamer` in line with it. Covered by two new regression
      tests in `ClipboardTextStreamerTests.cs`.
- [x] `WebSocketAgentServer.RunAsync`'s per-client `Task.Run(() =>
      HandleClientAsync(...))` had no exception handling at all — a malformed
      JSON message (`JsonNode.Parse` throwing on invalid input) or any
      connection-level error would fault the fire-and-forget task silently;
      the client just disconnects with zero trace. Split into
      `HandleClientAsync` (catches and logs) wrapping the renamed
      `HandleClientCoreAsync` (the original logic, unchanged).
- [x] `StartClipboardStream` and `StartFrameStream`'s `Task.Run` bodies only
      caught `OperationCanceledException`; any other exception (e.g. from the
      `onClipboardText`/`onFrame` broadcast callbacks, which can throw on
      socket errors) would silently end that stream forever. Added a
      catch-all with `Console.Error.WriteLine` to both, so a stream dying
      unexpectedly is at least visible in `agent.stderr.log` instead of
      indistinguishable from "nothing to broadcast."

## Reviewed, No Change Needed

- `AgentSession.HandleAsync` already wraps every message handler in a
  top-level `try/catch` that converts exceptions into `handler_failed` error
  responses instead of crashing or swallowing them — this was already the
  right pattern.
- `GdiWindowFrameCapture` already disposes its `Bitmap`/`Graphics`/HDC
  correctly (`using` plus a zero-checked `finally` for the HDC release with
  no double-release path).
- `WindowFrameStreamer` was already correct; it was the reference pattern
  used to fix `ClipboardTextStreamer`.
- `SingleInstanceGuard` was already covered by the earlier same-day fix and
  its regression test.

## Verification

- `dotnet test apps/windows-agent/tests/VeilAgent.Tests` — 11/11 pass (9
  existing + 2 new for `ClipboardTextStreamer`).
- `dotnet build`/`dotnet publish --runtime win-arm64` both succeed.
- Not re-verified live against the real Windows guest in this pass — the dev
  VM had accumulated enough same-day reboot/repair cycles that further live
  verification wasn't reliable (see the mutex-fix checklist's "Second
  Follow-Up" section). These are defensive/diagnostic changes (they change
  what gets logged, not the happy-path behavior), so the risk of a live
  regression is low, but flagging honestly rather than claiming a live pass
  that didn't happen.
