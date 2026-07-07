# DPI-Aware Capture Feasibility Spike

Date: 2026-07-07

Goal: scope the "Retina scaling / frame latency" roadmap item that the v1.5
plan explicitly deferred as needing its own feasibility research before any
implementation plan was possible. This turned out to split cleanly into two
independent halves of very different size:

- **Retina/DPI correctness** — the guest agent was never DPI-aware, so
  Windows silently virtualized every `GetWindowRect`/`PrintWindow` call to a
  96 DPI baseline and scaled the result to match, regardless of the window's
  real DPI. That means captured bitmaps were blurry upscales of the true,
  higher-resolution content on any HiDPI/scaled Windows display — a single,
  well-scoped fix (declare Per-Monitor-V2 DPI awareness, read the real DPI).
  **This is what this pass implements.**
- **Frame latency** (250ms GDI `PrintWindow` polling, no push-based capture)
  is a genuinely separate, harder problem needing a capture-backend
  investigation (Windows.Graphics.Capture/DXGI vs. the current GDI polling
  loop) — **left explicitly deferred**, unchanged by this pass.

## Implementation

- `ProcessDpiAwareness.EnablePerMonitorV2()` (new): calls
  `SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)`
  once at the very top of `Program.cs`, before any other agent code runs (and
  well before `WindowsDesktop`'s first P/Invoke call, all of which happen in
  instance methods invoked later, never at construction time — confirmed via
  code review before shipping). Requires Windows 10 version 1703+; falls back
  silently on older builds (agent keeps running with virtualized-96-DPI
  capture, exactly the pre-existing behavior).
- `GdiWindowFrameCapture.GetWindowScale(hwnd)` (new): reads `GetDpiForWindow`
  and reports `dpi / 96.0` instead of the previous hardcoded `Scale: 1`.
  Falls back to `1.0` for an invalid handle, a non-Windows platform, or a
  missing API entry point.
- `docs/protocol.md`: documented `window.frame.scale`'s real meaning.
- **Host: deliberately zero changes.** Code review specifically sanity-checked
  this: `WindowsAppFrameSurface.swift`'s `Image(nsImage:).resizable()`
  discards the underlying `NSImage`'s `.size` metadata and stretches based on
  pixel content plus the SwiftUI-computed layout frame — so a captured PNG
  with genuinely more real pixels (from DPI-aware capture) already renders
  sharper at the same on-screen size with no host code change needed. `scale`
  is plumbed through the wire format for future consumers, not consumed yet.

## Real Regression Risk Found During Code Review (fixed before live verification)

The review caught a consequence of enabling DPI awareness that the first
draft missed entirely: `WindowsDesktop.GetWindowBounds` — which feeds
`window.created`'s `bounds` field — also calls `GetWindowRect`. Enabling
Per-Monitor-V2 awareness changes what that API returns from virtualized
96-DPI-equivalent logical coordinates to **real physical pixel coordinates**.
On any Windows guest configured at other than 100% scaling (the default on
most modern HiDPI panels), every launched app's reported bounds would
suddenly be ~1.5-2x larger for the exact same on-screen window size —
`WindowsAppWindowPlacement.initialFrame` on the host (`apps/mac-host/Sources/
VeilHostCore/WindowsAppWindowPlacement.swift`) has hardcoded point-space
thresholds (`preferredMinimumWidth = 1040.0`, `isCompactUtilityWindow`
classification, etc.) that assume `bounds` is in the same units it's always
been in. Left unfixed, this would have silently broken mirrored-window
placement/sizing on any scaled Windows display, entirely undocumented.

### Fix

`GetWindowBounds` now normalizes the raw physical-pixel rect by the window's
real DPI scale (reusing `GdiWindowFrameCapture.GetWindowScale`) before
building the `WindowRect` sent over the wire, so `window.created.bounds`
keeps reporting exactly what it always has — decoupled from the separate,
intentionally-real-DPI `window.frame` capture path. `window.frame.width`/
`height`/`scale` carry the genuinely higher-resolution numbers;
`window.created.bounds` does not change meaning.

Also fixed two smaller review findings while in the area: an uncited
Windows-version platform-support claim (CLAUDE.md requires linking official
documentation when discussing support — added the actual Microsoft Learn
citation), and a doc comment that described host-side `scale` consumption
that doesn't actually exist (corrected to describe the real, automatic
benefit via unmodified PNG stretching instead).

## Verification

- `swift build` / `swift test`: 242/242 passing (no Swift changes needed,
  confirms nothing else regressed).
- `dotnet build` / `dotnet test` (`VeilAgent.Tests`): 22/22 passing, including
  new `GdiWindowFrameCaptureTests.cs` covering `GetWindowScale`'s fallback
  behavior (non-Windows, invalid handle).
- `harness/windows-agent-contract`: 19/19 passing (unaffected by this pass).
- Live VM (`veil-vmctl app-window-proof`): launched Notepad and inspected
  the resulting `window.created.bounds` (600x393 at x=78,y=78 — consistent
  with prior sessions' runs at the same window size, confirming the
  normalization fix introduced no regression) and the first `window.frame`
  (`scale: 1`, `width: 600`, `height: 393` — dynamically computed via
  `GetDpiForWindow` rather than a hardcoded literal, correctly reporting 1.0
  because this test VM's guest Windows display runs at 100% scaling).
- Not exercised live: a genuinely non-1 `scale` value, since doing so would
  require changing the test VM's Windows display scaling setting (a
  multi-step UI change carrying its own live-VM risk) for a currently-inert
  metadata field. `GetWindowScale`'s `dpi / 96.0` arithmetic and fallback
  paths are covered by unit tests instead; flagging this as the one gap for
  whoever picks up an actual host-side consumer of `scale` later.

## Still Explicitly Deferred

- **Frame latency** (the 250ms GDI `PrintWindow` polling loop): needs its own
  investigation into whether a push-based capture backend
  (Windows.Graphics.Capture/DXGI) is worth the added complexity over the
  current polling approach. Not touched by this pass.
- **Drag and drop**, **Windows notifications**: unchanged from the original
  v1.5 plan's deferral — each still needs its own protocol/feasibility work
  before an implementation plan makes sense.
