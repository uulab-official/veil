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
- [x] Treat the Windows installer ISO as install-time media only: installed Windows profiles boot from disk without requiring or attaching the ISO.
- [x] Stop regenerating/attaching automatic install media after guest-agent evidence exists, and avoid recopied guest-agent bundle directories when contents are unchanged.
- [x] Add a Mark Windows Installed app/CLI transition so desktop proof can detach installer media before the guest agent connects.
- [x] Convert the main shell to a single-window scene and close duplicate main windows so Veil cannot present two primary VM control surfaces.
- [x] Prioritize the installed-runtime CTA as Open Windows App, then Install Agent, then Stop Windows, matching the app-runtime product loop.
- [x] Keep mirrored Windows apps out of the main VM screen: Notepad renders in its own macOS window while the main shell remains a launcher/status surface.
- [x] Size the Notepad bridge window from the guest HWND bounds so it opens like a real desktop app instead of a small preview.
- [x] Generalize host launch from Notepad-only to selected `appId` so inbox apps can open as separate macOS windows.
- [x] Add a first Windows agent app catalog for Notepad, Calculator, and Paint instead of hard-coding a single launch target.
- [x] Add a menu bar Windows Apps launcher so live agent app launches can start without opening the main Veil control window.
- [x] Generalize protocol launch acceptance helpers and fake-agent launch replies beyond Notepad while preserving the Notepad MVP fixture.
- [x] Preserve guest HWND aspect ratio when opening macOS app windows so compact apps like Calculator are not inflated into generic VM-sized panes.
- [x] Cascade multiple mirrored Windows app windows within the visible display instead of stacking every app at the same centered origin.
- [x] Hide the Veil launcher after a real guest-agent app launch so the mirrored Windows app becomes the foreground Coherence-style experience.
- [x] Use edge-to-edge transparent host chrome for mirrored Windows app windows while keeping the logical app title for accessibility and Window menu identity.
- [x] Add a menu bar Running Windows Apps section so hidden or covered mirrored app windows can be brought forward without reopening the Veil launcher.
- [x] Add menu-bar close for running Windows apps that asks the guest to close the HWND before removing the local macOS mirror window.
- [x] Document the UTM/Parallels reference notes behind the running-app menu and HWND-to-NSWindow management direction.
- [x] Surface Windows runtime status and running app count at the top of the menu bar menu, following UTM's first-class status model but scoped to Veil's app-runtime loop.
- [x] Add menu-bar Close All for running Windows apps so multiple mirrored HWND sessions can be ended from one stable host surface.
- [x] Route Dock reopen and main-window hiding through launcher visibility status so Coherence runs bring Windows app windows forward instead of reopening duplicate launchers.
- [x] Open queued Windows apps from the menu bar without first reopening the main launcher once the guest agent can fulfill the pending launch.
- [x] Add a menu-bar Bring Windows Apps Forward command so hidden Coherence windows can be restored from the stable menu surface without opening the launcher.
- [x] Add `app-runtime-action --action stop-runtime` so automation can move from quiet-ready Windows app sessions to local runtime stop without dropping into QEMU-specific commands.

## Next

- [ ] Verify one-window startup with a running Windows 11 Arm install and guest-agent connection.
