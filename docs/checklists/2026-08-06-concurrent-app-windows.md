# Concurrent Windows App Windows

Date: 2026-08-06

First **v1.5 (Daily Use)** item. Also the largest remaining user-visible gap
against Parallels: Veil showed one Windows app window at a time.

## What Was Actually Wrong

The restriction lived in exactly one place — a guard in
`WindowsAppWindowPresenter.showWindow(for:)`:

```swift
guard windowsById.isEmpty else {
    return
}
```

Everything else in the stack was already built for many windows:

- The presenter stores `[String: NSWindow]` keyed by window id, plus a
  `windowOrder` array for foreground tracking.
- `WindowsAppWindowPlacement.initialFrame(for:visibleFrame:existingWindowCount:)`
  implements a cascade offset for additional windows. It was **dead code**:
  `existingWindowCount` was always 0 because a second window never got created.
- `HostDashboardModel` appends to `mirrorSessions`/`activeWindows` and never
  truncates or replaces.
- Every harness contract already requires
  `macWindowIntegration.mirroredWindowCount === mirrorSessions.length` and
  `visibleSurfacePolicy.expectedVisibleSurfaceCount === mirrorSessions.length`.
  Nothing anywhere required 1.
- The reconnect restore path already loops over an array of restored launches,
  and both call sites already loop over the result.

So the second window was constructed nowhere, silently. No error, no message,
no state change — a launch simply did nothing visible.

Notably `oneScreenUX` was **not** the blocker, despite the name. It is a surface
*family* contract: it forbids showing the launcher alongside app windows, and
requires a menu/Dock recovery path. Three app windows with a hidden launcher
satisfies it already.

## Track A: Let Windows Coexist

- [x] Remove the single-window guard.
- [x] Cascade placement is now reachable, so a second window does not land exactly
      on top of the first.
- [x] Rewrite the presenter test that asserted the restriction. It previously
      locked in `visibleWindowIds == ["hwnd:0001"]` after three different windows
      were shown, which is the behaviour being removed.

## Track A2: The Focus-Stealing Bug the Guard Was Hiding

Removing the guard exposed a real defect. `showWindow(for:)` called `present()`
on **every** call, including refreshes of an already-open window, and `present()`
does `makeKeyAndOrderFront` plus `NSApp.activate`.

Frames, window updates, and reconnect races re-present a session several times a
second. With one window that was invisible — raising the only window changes
nothing. With two, **every frame arriving for a background window would pull it
in front of the window the user was typing in**, several times a second. Lifting
the guard without this would have made concurrent windows unusable.

- [x] Content refreshes update in place and leave the foreground order alone.
- [x] Raising is opt-in via `bringToFront`, passed only by deliberate launch,
      restore, and focus actions. Newly created windows still always appear.
- [x] Regression test that repeated refreshes of a background window do not change
      `foregroundWindowId`, and that an explicit focus still does.

## Track B: Stop Recording a Fake Window Count

`refreshRestoreIntentFromOpenWindows()` wrote `[appId: 1]` for every app no
matter how many windows that app had open, while the field is documented as a
diagnostic record of "how many windows were open".

- [x] Record the real per-app window count.

Restore behaviour is deliberately **unchanged**: `restorableAppIdsForLaunches()`
still issues one launch per app. That is not a bug. A second launch of an app
that already owns a window reuses the existing HWND, so replaying a count would
either no-op or open duplicate Windows processes. Additional windows of the same
app arrive from the guest discovery stream instead.

## Scope: Multiple Apps, Not Yet Multiple Windows Per App

This ships **several different apps side by side**. It does not ship several
windows of the *same* app, and the difference is worth being precise about.

A second window of one app can only arrive from the guest's async discovery
stream, and `updateWindowState(_:)` deliberately refuses to create a macOS
window for an HWND the user never asked for. That provenance rule is still
correct — an unrequested window appearing on screen is worse than a missing one —
and lifting it needs an explicit multi-document design, which
`docs/checklists/2026-07-10-default-app-window-stability.md` already lists as an
open item. Parallels does both; Veil now does one of the two.

## Non-Goals, Stated Rather Than Skipped

- **Restore while windows are open.** `canRestoreMirrorSessions` and
  `canReconnectRestoreMirrorSessions` still require `mirrorSessions.isEmpty`.
  Restore means "reopen my previous session", which only makes sense from an
  empty state; restoring into a half-populated screen needs its own merge rules.
- **Per-window frame budget.** Every extra mirrored window is another frame
  stream. Nothing here measures what N concurrent streams cost, and the frame
  pipeline still has no numbers behind it at all.

## Guest Side: Already Multi-Stream

Checked rather than assumed, because a host that can open three windows is
useless if the guest only streams one.

`WebSocketAgentServer` holds
`ConcurrentDictionary<string, CancellationTokenSource> frameStreamsByWindowId`.
`StartFrameStream` keys by `window.WindowId`: it cancels only a pre-existing
stream for that *same* window (the re-subscribe case), stores its own token
source under that window's id, and its `finally` removes only its own entry.
`StopFrameStream` likewise removes one window.

So the guest already runs one capture loop per window concurrently. Nothing on
the guest needed changing, which matches the rest of this slice: the whole stack
was built for many windows and a single presenter guard was the only thing
stopping it.
- **Window count limit.** No cap is imposed. If N streams turn out to be
  unaffordable, the fix belongs where it is measured, not as an arbitrary guard.

## Verification Status

**Not executed.** Shell command execution has been unavailable for this entire
session and it is not a permissions problem: `echo` returns exit 1 with no
output.

```bash
cd apps/mac-host && swift build && swift test
cd harness/app-runtime-status && npm test
```

## Remaining Live Verification

- [ ] Open Notepad, then Calculator, then Paint. All three must be visible as
      separate macOS windows at once, cascaded rather than stacked exactly.
- [ ] Confirm each window's input goes to its own guest window: type in Notepad
      while Calculator is open and confirm nothing lands in Calculator.
- [ ] Confirm each window renders its own frames, and that closing one leaves the
      others streaming.
- [ ] Confirm the launcher stays hidden with three windows open and returns when
      the last one closes.
- [ ] Measure frame throughput with three streams against one, using
      `veil-vmctl frame-pipeline-report`. This is the first case where the
      unmeasured frame pipeline can plausibly fall over, and it is the reason the
      measurement runs matter more now than before.
- [ ] Confirm idle suspend still triggers only after the **last** window closes.
