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

## Next

- [ ] Add protocol messages for frame stream subscribe/unsubscribe.
- [ ] Replace the placeholder surface with captured Notepad frames from the Windows guest agent.
- [ ] Validate keyboard input inside Windows 11 Arm with Notepad focused.
- [ ] Persist and restore mapped app windows after VM reconnect.
