# Resizing A Mirrored Window Grew The Black Bars

Date: 2026-08-14

## What Was Wrong

Drag the corner of a mirrored Windows app window and the Windows window does not change
size. The protocol has **no host-to-guest resize message at all** — searching
`docs/protocol.md` for "resize" turns up one sentence, and it is the guest noting that a
resize changes its capture buffer length.

`WindowsAppWindowPresenter` conforms to `NSWindowDelegate` but implements no
`windowDidResize` or `windowDidEndLiveResize`, so nothing on the host even observes the
gesture.

What the user saw instead: `WindowsAppFrameSurface` renders the frame with `.scaledToFit()`
over `Color.black`. Any shape other than the guest window's produced **black letterbox
bars**. The Mac window grew and the app sat in the middle of it, unchanged, framed in black.

That is a long way from Parallels, where resizing the Mac window resizes the Windows window
and the app reflows.

## What Changed

Not the feature. A mitigation that makes the existing behaviour coherent instead of broken.

- [x] `WindowsAppWindowPlacement.contentAspectRatio(for:)` — the guest window's shape, or
      `nil` for a degenerate size.
- [x] `WindowsAppWindowPlacement.minimumContentSize(for:shortestSide:)` — a minimum on the
      same ratio.
- [x] `WindowsAppWindowPresenter.applyResizeConstraints(to:for:)` sets
      `contentAspectRatio`, so macOS constrains live resize to the guest's shape. The window
      still resizes, the image still scales, and it can no longer letterbox or distort.
- [x] Re-applied on every refresh, because the guest window really can be resized from inside
      Windows and the lock has to track it rather than pin the shape it had at launch.
- [x] 8 tests.

## Decisions

**The fixed `contentMinSize` of 520×360 had to go.** A fixed minimum fights an aspect-ratio
lock: for a window whose guest ratio does not match the minimum's, AppKit has to violate one
of the two. Deriving the minimum from the same ratio removes the conflict, and a test asserts
the minimum sits exactly on the locked ratio so a window can shrink to it without breaking
the lock.

**The floor applies to the shorter dimension, not the width.** A Calculator-shaped window
(520×720) gets a 320-wide minimum; a browser-shaped one gets a 320-tall minimum. Flooring
width would have made tall utility windows enormous.

**The minimum never exceeds the guest window.** A 200×150 tool window would otherwise be
handed a minimum it cannot satisfy.

**Degenerate guest bounds leave the window freely resizable.** A ratio computed from a zero
dimension is a ratio derived from nothing, and locking to a guess is worse than not locking.

**Clearing the lock uses `contentResizeIncrements`, not `resizeIncrements`.** AppKit pairs
content-space aspect ratio with content-space increments, and frame-space with frame-space.
Clearing the wrong pair would leave a stale ratio from an earlier refresh in place — a bug
that would only show up on the specific sequence of valid bounds followed by degenerate
bounds.

**Existing windows are not snapped to the ratio.** `updateExistingWindow` deliberately
preserves the user's size and position (a contract recorded in `docs/roadmap.md`), so the lock
applies from the user's next resize onward. New windows do not need snapping: `initialFrame`
already scales width and height by the same factor, so a freshly placed window is already on
the guest ratio. A test pins that, because if it ever stopped being true the lock would visibly
snap a window the first time the user touched its corner.

## What This Is Not

It does not resize the Windows window, and it should not be mistaken for having done so. A
user who wants a bigger Notepad still gets a bigger *picture* of the same Notepad, and text
will be interpolated rather than re-rendered.

The real feature needs a new host-to-guest message:

1. `window.resize.request` carrying `windowId`, `width`, `height` in the same logical
   ~96-DPI units `window.created.bounds` already uses (see
   `docs/checklists/2026-08-10-retina-scaling-finding.md` — bounds are logical, frame
   dimensions are physical, and mixing them up halves every window on a scaled guest).
2. A guest handler calling `SetWindowPos`, rejecting untracked HWNDs with
   `window_not_tracked` like the other windowId-bearing messages.
3. Host-side debouncing on `windowDidEndLiveResize` rather than per-frame during the drag,
   since each message currently opens its own WebSocket (see
   `docs/checklists/2026-08-13-host-guest-contract-audit.md`).
4. Accepting that the guest is authoritative: the app may refuse the size, or clamp it to its
   own minimum, and the answer arrives as the next `window.updated`. The host must not assume
   the size it asked for.

Point 4 is the reason this is worth doing carefully rather than quickly. A resize that the
host believes happened and the guest refused would put the two ends into permanent
disagreement about the window's shape, which is exactly the class of bug the aspect lock is
papering over right now.

Deliberately not attempted here: it is a wire-contract change needing C# and Swift compiled
together, and neither `swift build` nor `dotnet test` runs in this environment.

## Not Verified

No compiler or window server has seen this. Specific risks:

- `contentAspectRatio` is applied in `configure(_:for:)`, which `updateExistingWindow` calls
  before restoring `preservedFrame`. Setting an aspect ratio does not resize a window, so the
  preserved frame should survive — but that ordering wants a live check.
- Whether AppKit honours `contentMinSize` and `contentAspectRatio` together as intended when
  the minimum sits exactly on the ratio.
- Whether removing the 520×360 floor makes any window uncomfortably small in practice. The
  new floor is 320 on the shorter side, which is smaller than before for wide windows.
