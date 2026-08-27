# Minimized Windows Were Still Streaming, And A Crash Found On The Way

Date: 2026-08-15

Two findings. The second one is more serious than the first.

## 1. A Minimized Window Cost Full Price

`WindowsAppWindowPresenter` is an `NSWindowDelegate` and implemented no
`windowDidMiniaturize`. Nothing on the host observed a minimize, so collapsing a mirrored
window into the Dock left the guest capturing its pixels, byte-comparing them against the
previous buffer, PNG-encoding them, and sending them, while the host decoded and composited
every frame — for a window showing nothing.

With three apps open and two minimized, most of the frame pipeline's cost was going to
windows nobody could see. This is the same principle as unchanged-frame heartbeats and idle
suspend: stop paying for what nobody sees.

- [x] `windowDidMiniaturize` / `windowDidDeminiaturize` on the presenter, forwarded as
      `onWindowVisibilityChange(windowId, isVisible)`.
- [x] `HostDashboardModel.pauseFrameStream(windowId:pausedAt:)` and
      `resumeFrameStream(windowId:resumedAt:)`.
- [x] Paused ids cleaned up in `removeWindowState`, so a window minimized and then closed does
      not stay paused forever — a later window reusing the same HWND would be treated as
      already paused and never resubscribed.
- [x] 10 tests.

### The trap, which was most of the work

Unsubscribing is trivial. Not tripping the staleness ladder is not.

A stream with no frames arriving escalates `restart-frame-subscription` →
`recover-window-capture` → `reopen-windows-app`. A naive pause would therefore offer to
**relaunch the user's app** a few seconds after they minimized it, and the automatic sweeps
would resubscribe and re-focus a window they deliberately put away.

The first design cleared `frameStreamRequestedAt`, which drops the session into the same state
as one that has not asked for frames yet — no timeout, no escalation. Checking it against the
harness contract killed it: `harness/app-runtime-status` requires `frameStreamRequestedAt` on
any capture session with no received frames, so every paused window would have failed report
validation.

What shipped instead: keep `frameStreamRequestedAt`, and exclude paused windows from
`restartStaleFrameSubscriptions` and `recoverEscalatedFrameCaptures`. Those sweeps are the only
things that raise `frameStreamRestartCount`, and the ladder is climbed by that count — so with
the sweeps declining to touch a paused window, the count stays at zero and the ladder can never
be climbed. A test pins the count at zero after ten simulated minimized minutes, and another
pins that an *unpaused* stale window is still swept, because scoping the exclusion too widely
would have disabled recovery for everything.

### Known limitation

A long-minimized window still reports `frameStreamStatus: "stale"`. That is not false — no
frames are arriving — but automation cannot distinguish "stale because minimized" from "stale
because broken". Fixing it properly means an `isFrameStreamPaused` field on the report session
plus a validator rule, which would be the fifth field made optional for fixture
back-compatibility. Recorded rather than done; the harm (spurious recovery actions) is already
prevented.

## 2. An Index Held Across `await` Could Crash

Found while modelling pause/resume on the existing subscription helpers.

`restartFrameSubscription` and `recoverFrameCapture` both did this:

```swift
guard let index = mirrorSessions.firstIndex(where: { $0.id == windowId }), ... else { return false }

do {
    try await service.unsubscribeWindowFrames(windowId: windowId)
    try await service.subscribeWindowFrames(windowId: windowId)
    mirrorSessions[index].captureState = .pending   // index is from before the awaits
```

`mirrorSessions` is main-actor state, which makes holding an index across suspension points
look safe. It is not: an `await` yields, and a `window.closed` arriving in that gap runs
`removeWindowState` and shrinks the array. The index is then **out of bounds** — a crash, not a
wrong value. A reorder is quieter and worse, applying the mutation to a different window.

`recoverFrameCapture` is the more exposed of the two: it awaits `focusWindow` first, so the
window is confirmed to exist and *then* three more suspension points pass before the index is
used.

- [x] Both re-resolve the index after the awaits, through
      `resolvedMirrorSessionIndex(for:)`, and return `false` if the window is gone.
- [x] Both had to rename their pre-await binding, since re-declaring `index` in the same scope
      is a compile error.

### Also fixed here

`recoverFrameCapture` set `phase = .failed` on error. It is reached from
`recoverEscalatedFrameCaptures`, which runs automatically, and `.failed` renders as
"Connection failed" in the runtime status line and the menu bar title. An automatic recovery
attempt that did not take was reporting Windows as disconnected. Same class as the two fixed
on 2026-08-13; this was the last one in the frame path.

## Not Verified

Nothing compiled or run. The shell returns exit 1 with empty output for every command.

Highest-risk items:

- Whether `windowDidMiniaturize` fires before or after AppKit finishes the animation, and
  whether the resulting unsubscribe races the last in-flight frame. A late frame for a paused
  window would be applied and then sit as `latestFrame` until resume clears it — untidy but not
  harmful.
- `pauseFrameStream` and `resumeFrameStream` both require `hasLiveAgentConnection`. During a
  reconnect, a minimize would not pause. The window resumes normally on restore, so the failure
  mode is "kept streaming", which is the old behaviour rather than a new bug.
- Whether the report contract holds for a paused session in practice. The reasoning is from
  reading `validate-app-runtime-status.mjs`, not from running it.
