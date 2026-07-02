# Coherence App Window Checklist

Goal: make Veil's product direction visible as "Windows app as a macOS window" instead of only a VM console.

## Completed

- [x] Store active Windows window sessions from `window.created` events in `HostDashboardModel`.
- [x] Keep one active session per HWND so the host can map one Windows window to one macOS window.
- [x] Add an AppKit `NSWindow` presenter keyed by `windowId`.
- [x] Add a main-screen Windows Apps On Mac panel with an `Open As Mac Window` action.
- [x] Wire Command-Return to the same separate-window launch path.
- [x] Show a placeholder app surface until guest window capture frames are available.
- [x] Forward macOS mirrored-window mouse clicks and drags to the Windows HWND through `input.mouse`.
- [x] Add Windows agent `input.mouse` handling via HWND `PostMessage` and advertise the input capability from the real agent.
- [x] Forward macOS mirrored-window keyboard events through `input.key`, including Command-to-Ctrl shortcut mapping.
- [x] Add Windows agent `input.key` handling via HWND `WM_KEYDOWN` and `WM_KEYUP`.
- [x] Sync macOS text clipboard to the Windows guest before forwarded paste shortcuts.
- [x] Add Windows agent `clipboard.text.set` handling with STA clipboard writes.
- [x] Add guest-to-host automatic text clipboard sync with loop prevention.
- [x] Add protocol messages for frame stream subscribe/unsubscribe.
- [x] Subscribe to capture streams after launching a capture-capable Windows app window.
- [x] Unsubscribe from capture streams before closing mirrored Windows app windows.
- [x] Map mirrored-window mouse input through the aspect-fit captured frame rect instead of the full letterboxed host view.
- [x] Restore mapped Notepad app windows after the live agent reconnects.
- [x] Persist mapped app window intent across host app relaunch.
- [x] Make fake-agent advertise capture support and broadcast fixture `window.frame` events to host event clients.
- [x] Extend fake-host launch flow to subscribe to Notepad capture and verify a received `window.frame`.
- [x] Make mirrored app windows frame-first by removing header, debug caption, and status tiles once capture frames arrive.
- [x] Extract macOS-to-Windows key mapping into tested host-core logic for mirrored app windows.
- [x] Foreground and focus the guest HWND before forwarding mouse or keyboard input from mirrored app windows.
- [x] Add an executable fake-host Notepad input smoke scenario for real-agent keyboard validation.

## Next

- [ ] Replace the placeholder surface with captured Notepad frames from the Windows guest agent.
- [ ] Validate keyboard input inside Windows 11 Arm with Notepad focused.
