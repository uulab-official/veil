# Real Frame Integrity Checklist

Goal: prevent the Windows App Runtime from presenting a synthetic image as a
working mirrored Windows app window.

## Completed

- [x] Removed the guest agent's synthetic 1x1 PNG fallback from initial HWND
      capture and continuing frame streaming.
- [x] Preserve `app.launch.response` and `window.created` when the initial
      capture fails, so the macOS host can open the native window and start the
      real frame stream instead of losing the launched app.
- [x] Keep the initial stream sequence at `1` when no initial frame exists,
      avoiding an artificial gap before the first real image arrives.
- [x] Skip failed stream ticks and retain the existing host timeout, restart,
      capture-recovery, and reopen policies for a stream that has no real
      image.
- [x] Add .NET coverage for initial-capture failure and for recovery when the
      next stream tick returns a real frame.
- [x] Update the protocol contract and Windows-agent source contract so a
      synthetic bootstrap frame cannot be reintroduced silently.

## Remaining Live Verification

- [ ] Trigger a real transient `PrintWindow` or screen-copy failure on the
      Windows 11 Arm guest and confirm the macOS app shows the existing waiting
      or stale-screen recovery state, never a blank stretched placeholder.
- [ ] Measure first-real-frame recovery latency on Notepad, Calculator, and
      Paint against the shared Daily Use latency budget.
