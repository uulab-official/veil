# Resizing A Mirrored Window Grew The Black Bars

Date: 2026-08-14

## What Was Wrong

Drag the corner of a mirrored Windows app window and the Windows window must follow the
Mac mirror. Previously the protocol had **no host-to-guest resize message at all** and
the Windows window did not change size.

Previously, `WindowsAppWindowPresenter` conformed to `NSWindowDelegate` but implemented no
`windowDidResize` or `windowDidEndLiveResize`, so nothing on the host even observed the
gesture.

What the user saw instead: `WindowsAppFrameSurface` renders the frame with `.scaledToFit()`
over `Color.black`. Any shape other than the guest window's produced **black letterbox
bars**. The Mac window grew and the app sat in the middle of it, unchanged, framed in black.

That is a long way from Parallels, where resizing the Mac window resizes the Windows window
and the app reflows.

## What Changed

- [x] `WindowsAppWindowPlacement.contentAspectRatio(for:)` — the guest window's shape, or
      `nil` for a degenerate size.
- [x] `WindowsAppWindowPlacement.minimumContentSize(for:shortestSide:)` — a minimum on the
      same ratio.
- [x] `WindowsAppWindowPresenter.applyResizeConstraints(to:for:)` sets
      `contentAspectRatio`, so macOS constrains live resize to the guest's shape. The window
      still resizes, the image still scales, and it can no longer letterbox or distort.
- [x] Re-applied on every refresh, because the guest window really can be resized from inside
      Windows and the lock has to track it rather than pin the shape it had at launch.
- [x] `window.resize.request`/`window.resize.response` added to Swift, C#, and the executable
      protocol validator, with request and response fixtures.
- [x] `windowDidEndLiveResize` sends one final logical content size instead of flooding the
      guest for every drag pixel.
- [x] The Windows agent validates bounds, converts logical units through the HWND DPI, calls
      `SetWindowPos` without activation, and returns the actual applied bounds.
- [x] 20 macOS presenter tests, 2 host client/protocol resize tests, 4 Windows agent resize
      tests, and protocol fixture validation pass.

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

## Remaining Verification

- The automated contract and fake desktop tests prove routing, validation, DPI-unit intent, and
  actual-bounds reporting. A live Windows resize proof still needs to run on the real guest and
  measure the `window.updated`/key-frame latency after a drag.
- An app may clamp or reject a requested size; the next `window.updated` event remains the source
  of truth. The host does not claim every app supports arbitrary client dimensions.
- This feature fixes window geometry and capture resolution. It does not add Parallels-level GPU
  acceleration; the current QEMU display remains the verified virtio-GPU/VNC path.
