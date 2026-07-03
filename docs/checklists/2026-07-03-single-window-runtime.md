# Single-Window Runtime Checklist

Date: 2026-07-03

Goal: move Veil from a Veil shell plus separate QEMU Cocoa display toward a UTM-style single main-window runtime.

## Completed

- [x] Identify the two-window cause: Veil opens its SwiftUI shell while QEMU's `-display cocoa` creates a second native macOS window.
- [x] Stop treating Start as an "open display" action in product copy.
- [x] Rename the temporary external display affordance to "Native QEMU Display" so it is clearly a fallback, not the target experience.
- [x] Keep the main Veil window as the default place for runtime status, screenshots, app-frame proof, and app launch.
- [x] Document that embedded display is the UTM-class target and QEMU Cocoa is temporary.

## Next

- [ ] Add an embedded display provider spike that can render the QEMU guest surface inside the main SwiftUI/AppKit window.
- [ ] Route pointer and keyboard input through the embedded display provider before demoting the native QEMU window completely.
- [ ] Keep native QEMU display available only as an advanced recovery fallback.
- [ ] Replace screenshot-only setup evidence with a live embedded installer surface.
- [ ] Verify one-window startup with a running Windows 11 Arm install and guest-agent connection.
