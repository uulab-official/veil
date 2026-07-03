# Single-Window Runtime Checklist

Date: 2026-07-03

Goal: move Veil from a Veil shell plus separate QEMU Cocoa display toward a UTM-style single main-window runtime.

## Completed

- [x] Identify the two-window cause: Veil opens its SwiftUI shell while QEMU's `-display cocoa` creates a second native macOS window.
- [x] Stop treating Start as an "open display" action in product copy.
- [x] Rename the temporary external display affordance to "Native QEMU Display" so it is clearly a fallback, not the target experience.
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

## Next

- [ ] Turn the current screenshot evidence refresh into a live embedded display provider inside the main SwiftUI/AppKit window.
- [ ] Replace screenshot-only setup evidence with a live embedded installer surface.
- [ ] Keep native QEMU display available only as an advanced recovery fallback.
- [ ] Verify one-window startup with a running Windows 11 Arm install and guest-agent connection.
