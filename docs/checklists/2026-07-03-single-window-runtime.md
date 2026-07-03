# Single-Window Runtime Checklist

Date: 2026-07-03

Goal: move Veil from a Veil shell plus separate QEMU Cocoa display toward a UTM-style single main-window runtime.

## Completed

- [x] Identify the two-window cause: Veil opens its SwiftUI shell while QEMU's `-display cocoa` creates a second native macOS window.
- [x] Stop treating Start as an "open display" action in product copy.
- [x] Move the temporary external display affordance behind an explicit Open Recovery Display menu action so it is clearly a fallback, not the target experience.
- [x] Keep the main Veil window as the default place for runtime status, screenshots, app-frame proof, and app launch.
- [x] Document that embedded display is the UTM-class target and QEMU Cocoa is temporary.
- [x] Add a headless QEMU launch mode that rewrites app-started QEMU from `-display cocoa` to `-display none`.
- [x] Make the macOS app use headless single-window preview mode by default, with `VEIL_USE_NATIVE_QEMU_DISPLAY=1` as the explicit native-window fallback.
- [x] Record the display mode in QEMU launch diagnostics.
- [x] Surface the latest setup screenshot refresh time in runtime evidence so the single-window preview shows whether it is updating.
- [x] Classify setup preview evidence as fresh, stale, or unavailable so the main window can distinguish a live preview from old proof.
- [x] Mark the single-window preview live only when screenshot evidence actually changes after a capture refresh.
- [x] Refresh running console screenshot evidence every second once a preview file exists and force the SwiftUI image surface to rerender on each capture revision.
- [x] Route clicks on the single-window setup preview to QEMU QMP absolute pointer tap events so the embedded surface can become interactive.
- [x] Capture keyboard focus on the single-window setup preview and route Mac key events to QEMU key sequences.
- [x] Launch app-started QEMU with a loopback VNC display endpoint so the next embedded surface can consume live frames without opening a native QEMU window.
- [x] Promote the loopback endpoint into an explicit embedded display surface contract used by runtime evidence and the main SwiftUI display area.
- [x] Add a tested RFB parser for protocol handshake, server init, and raw framebuffer updates for the loopback VNC display surface.
- [x] Add a loopback RFB socket client and framebuffer renderer that converts raw VNC rectangles into RGBA frames.
- [x] Bind the RFB framebuffer renderer to the main SwiftUI/AppKit display surface so live VNC frames can replace screenshot fallback inside the Veil window.
- [x] Request raw RFB encoding during VNC session setup so QEMU sends frames the embedded renderer can decode reliably.
- [x] Add `veil-vmctl qemu-display-smoke` plus a Node harness validator to prove a live app-launched VNC endpoint can deliver one decoded frame.
- [x] Add CLI persistent launch support for the same single-window loopback display path as the app.
- [x] Make embedded display the default `veil-vmctl qemu-start` path and keep native QEMU Cocoa display behind `--native-display`.
- [x] Guard the runtime booter so frontmost/System Events automation only runs for the explicit native display fallback.
- [x] Detect already-running orphan QEMU processes by configured Windows disk path so an old native Cocoa display cannot silently coexist with a new embedded launch.
- [x] Remove normal VM-screen Native Display buttons so the product surface stays one-window by default.

## Next

- [ ] Verify one-window startup with a running Windows 11 Arm install and guest-agent connection.
