# Multiple Windows Per App

Date: 2026-08-09

Finishes the **v1.5** item Slice 9 (2026-08-06) deliberately left half-done.
Several *different* apps could already mirror side by side. Several windows of the
*same* app could not, and that is the more common case in real work: two Word
documents, three Explorer windows, a spreadsheet and its chart.

## Why It Was Blocked

Not by a window limit. By a **provenance rule** in
`HostDashboardModel.shouldAcceptTrackedWindowEvent(_:)`:

```swift
activeWindows.contains(where: { $0.windowId == event.windowId })
    || mirrorSessions.contains(where: { $0.id == event.windowId })
```

A `window.created` event for an HWND Veil never launched is ignored. A second
window of one app can only arrive that way — from the guest's async discovery
stream — so it was always ignored.

The rule is right about the thing it was protecting. The guest enumerates every
tracked process after a reconnect, and without this a leftover window from a
previous session, or something Windows opened on its own, would materialize as a
macOS window the user never asked for. An unrequested window appearing is worse
than a missing one.

## The Distinction the Old Rule Missed

There are two kinds of window Veil did not launch, and they are not the same:

1. **A window of an app the user already has open here.** The user opened Word;
   Word opened a second document window. The user's act of opening the app is the
   consent, and the new window is the app doing what they asked. This should
   appear.
2. **A window of an app never opened in this session.** A leftover process, or
   something Windows started by itself. This should not appear.

The old rule collapsed both into "did not launch it, ignore it". The new rule
separates them.

## Track A: Adopt, Narrowly

- [x] Accept a discovery-created window when its `appId` already has a tracked
      window in this session, and refuse it otherwise.
- [x] Require a non-empty title and non-zero bounds. A zero-sized or untitled
      top-level window is far more likely a tooltip, splash, or transient shell
      than a document.
- [x] Bound how many windows Veil will adopt for one app.

The bound is **not** a user preference and not a judgement about how many windows
someone should have. It bounds *guest-driven* creation, which the host does not
control: a misdetected transient window or a runaway enumeration loop would
otherwise open macOS windows without limit. Deliberate document windows will not
reach it in normal work. This is the opposite of the reasoning in Slice 9, where a
cap on *total* windows was refused — there the host was in control of every window
because each came from an explicit launch.

## What Deliberately Did Not Change

- **A second explicit launch of the same app still reuses its window.**
  `performAppLaunch` routes it to `restoreApp`, which focuses the existing HWND.
  That matches how macOS and Parallels behave: clicking an open app focuses it, and
  new documents are opened from inside the app. Opening a second blank window on a
  second click would be surprising.
- **Restore still launches once per app.** Additional windows are re-adopted from
  discovery afterwards. This is the point where Slice 9's fix pays off: that slice
  made `restorableAppWindowCounts` record the real per-app count instead of a
  hardcoded 1, and the count is now genuinely diagnostic — restore replays one
  launch and discovery brings the rest back.

## Non-Goals, Stated Rather Than Skipped

- **Window ordering across a restore is not preserved.** Adopted windows arrive in
  whatever order the guest enumerates them. Restoring a specific layout needs
  per-window geometry persistence, which is its own feature.
- **No per-app window list in the UI.** The Dock menu and status report count
  windows; they do not group them by app. Worth doing, not required for the
  windows to work.
- **Frame cost is still unmeasured.** Slice 9 already made N concurrent streams
  possible; this makes N larger in practice. The measurement it needs is the same
  one the frame pipeline has been missing for six slices.

## Verification Status

**Not executed.** Shell command execution has been unavailable for this entire
session; `uname -s` returns exit 1 with no output.

```bash
cd apps/mac-host && swift build && swift test
cd harness/app-runtime-status && npm test
```

## Remaining Live Verification

- [ ] Open Notepad, then use File > New inside Windows Notepad to open a second
      document. Both must appear as separate macOS windows.
- [ ] Confirm typing in one document does not land in the other.
- [ ] Close one document window and confirm the other keeps streaming.
- [ ] Restart the guest agent with two Notepad documents open and confirm both come
      back — one from restore, one from adoption.
- [ ] Confirm a leftover window from a *different*, never-opened app does **not**
      appear after a reconnect. This is the case the old rule existed to prevent and
      the one most likely to regress.
- [ ] Confirm idle suspend still waits for the last window of the last app.
