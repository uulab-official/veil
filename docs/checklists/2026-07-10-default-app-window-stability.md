# Default App Window Stability Checklist

Goal: opening Veil's normal Windows-app path must show one macOS app window per
Windows app, never a replay of stale documents or a duplicate-window cascade.

## Completed

- [x] Treat a persisted window count as diagnostic migration input, not an
  automatic restore queue.
- [x] Rewrite legacy persisted restore records to one window per app when the
  host model loads them.
- [x] Reuse an already tracked guest HWND when a user repeats the normal app
  launch action.
- [x] Ignore additional automatic `window.created` discovery events for the
  same app after its first app window is mirrored.
- [x] Ignore discovery events until the host has established a capture-capable
  live agent overview, preventing a startup placeholder from becoming a blank
  app window.
- [x] Treat asynchronous guest discovery as metadata-only in the normal path;
  only an explicit host launch or restore response may create a macOS window.
- [x] Cap the pre-alpha presenter at one visible Windows app window total;
  a user closes the active app before opening another app.
- [x] Keep automatic startup restore bounded to three reuse-only attempts.
- [x] Isolate the local QEMU stop unit test from the real QEMU launch-record
  directory so test fixtures cannot inspect the live Windows VM.
- [x] Cover legacy restore migration, repeated launch reuse, and duplicate
  same-app discovery in the macOS host test suite.

## Live Verification

- [x] Confirm the existing restore record with 21 historical Notepad entries
  is migrated to one `winapp_notepad` restore target.
- [x] Reconnect the currently running Windows 11 Arm guest agent, then launch
  the built host shell and visually confirm one visible Veil Notepad mirror
  window with a live frame (no launcher or duplicate app window).

## Follow-up

- [ ] Design an explicit multi-document action and restore ordering before
  allowing more than one mirrored window for the same app in the normal path.
- [ ] Keep guest-agent recovery separate from window creation: an unavailable
  agent must leave the launcher recoverable, not create placeholder windows.
