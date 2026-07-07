# Frame Latency — Windows.Graphics.Capture Feasibility Research

Date: 2026-07-07

Goal: research the harder half of v1.5's "better frame latency" item -- the
250ms GDI `PrintWindow` polling loop in `GdiWindowFrameCapture.cs` -- which
the DPI-aware capture pass earlier this session explicitly left deferred as
"needing its own capture-backend investigation." This document is that
research; **no code was written.**

## The question

Can the guest agent replace polling `PrintWindow` every 250ms with a
push-based capture API that delivers frames as the window actually redraws,
without requiring a bigger rewrite than the latency win is worth?

## Finding: Windows.Graphics.Capture works from an unpackaged Win32 app -- with one real catch

`Windows.Graphics.Capture` (WGC) is the modern, event-driven screen/window
capture API (`Direct3D11CaptureFramePool` + a `FrameArrived` event instead
of a poll loop). Critically, its core capture path is available to
**unpackaged Win32 apps directly** -- via `IGraphicsCaptureItemInterop::
CreateForWindow(HWND)`, no package identity needed for that part.
`CreateForWindow` needs Windows 10 version 1903 (build 18362) or later;
Windows 11 Arm clears that easily. Microsoft's own
[Win32CaptureSample](https://github.com/robmikh/Win32CaptureSample) is
exactly this scenario: a plain Win32 app capturing a single window via HWND.

**The catch**: WGC draws a mandatory yellow border around the captured
window by default, as a privacy/security indicator that a capture is in
progress. For Veil this would mean every mirrored Windows app window
permanently shows a yellow rectangle baked into the captured content --
a visible regression from the current clean `PrintWindow` capture, and
squarely against the "feels like a native Mac window" goal this whole
session's work has been pushing toward.

Removing the border (`GraphicsCaptureSession.IsBorderRequired = false`)
requires:
1. Package identity (the same **sparse package** technique researched for
   Windows notifications in
   `docs/checklists/2026-07-07-notifications-and-printer-feasibility.md`).
2. Declaring the `graphicsCaptureWithoutBorder` capability in that
   package's manifest.
3. A one-time runtime consent prompt via
   `GraphicsCaptureAccess.RequestAccessAsync(GraphicsCaptureAccessKind.Borderless)`.

### Strategic implication: this is the same infrastructure Windows notifications needs

Both "borderless frame capture" and "Windows notifications" are blocked on
the exact same underlying investment: a signed sparse package granting the
existing unpackaged guest agent process identity, plus a runtime consent
flow. Neither is a standalone blocker on its own merits -- they're two
features gated behind one shared piece of infrastructure Veil doesn't have
yet. That reframes the roadmap choice: instead of two separate feasibility
gaps, there's **one** infrastructure gap (sparse package + signing +
install-flow cert trust) that, once closed, unlocks both.

### GPU/virtualization concern -- addressed, not fully verified

WGC's capture path uses Direct3D 11 under the hood. QEMU/HVF's Windows 11
Arm guest has no real GPU passthrough today. This is not a hard blocker:
Microsoft's **WARP** (Windows Advanced Rasterization Platform) is the
officially documented, purpose-built software D3D11 fallback for exactly
"a VM with your GPU disabled, or without a display driver" and "headless
environments" -- DXGI enumerates a `Microsoft Basic Render Adapter` in
these cases and D3D11 apps (including capture APIs) run against it
transparently. This means WGC should *function* under Veil's current VM
configuration without new virtio-gpu work. What's **not verified** without
live benchmarking is whether WARP-backed capture actually delivers a
latency win over the current 250ms GDI poll, or whether software
rasterization overhead cancels out the push-based delivery advantage --
that can only be answered by implementing a prototype and measuring it
against the real guest, not by research alone.

## Recommendation

Don't implement standalone WGC capture yet -- shipping it *with* the yellow
border would be a visible regression, and shipping it *without* the border
requires the same sparse-package infrastructure the notifications feature
also needs. The right-sized next step is a **combined infrastructure spike**
covering:

1. Build and sign a sparse package for the existing unpackaged guest agent
   (the real new cost identified for notifications).
2. Extend the install flow (`Repair-VeilAgentConnectivity.ps1`-style
   elevated PowerShell) to trust the signing certificate.
3. Prove `GraphicsCaptureAccess.RequestAccessAsync(Borderless)` and
   `UserNotificationListener.Current.RequestAccessAsync()` both succeed
   against the same identity-bearing process, live, on the real QEMU/HVF
   Windows 11 Arm guest.

Once that infrastructure exists, borderless WGC capture and Windows
notifications become two independent, much smaller follow-up features
rather than two separate research-and-build efforts. This spike is sized
larger than the app-icons/DPI-capture/drag-and-drop passes earlier this
session (it touches code signing and package manifests, a genuinely new
category of guest-side work), so it's proposed as its own dedicated pass,
not attempted here.

## Sources

- [Screen capture - Windows apps | Microsoft Learn](https://learn.microsoft.com/en-us/windows/apps/develop/media-authoring-processing/screen-capture)
- [GraphicsCaptureItem Class (Windows.Graphics.Capture) - Windows apps | Microsoft Learn](https://learn.microsoft.com/en-us/uwp/api/windows.graphics.capture.graphicscaptureitem?view=winrt-28000)
- [Win32CaptureSample - GitHub](https://github.com/robmikh/Win32CaptureSample)
- [New Ways to do Screen Capture - Windows Developer Blog](https://blogs.windows.com/windowsdeveloper/2019/09/16/new-ways-to-do-screen-capture/)
- [GraphicsCaptureSession.IsBorderRequired Property - Windows apps | Microsoft Learn](https://learn.microsoft.com/en-us/uwp/api/windows.graphics.capture.graphicscapturesession.isborderrequired?view=winrt-20348)
- [About Window Graphics Capture yellow border - Microsoft Q&A](https://learn.microsoft.com/en-gb/answers/questions/591417/about-window-graphics-capture-yellow-border)
- [Windows Advanced Rasterization Platform (WARP) Guide - Win32 apps | Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/direct3darticles/directx-warp)
