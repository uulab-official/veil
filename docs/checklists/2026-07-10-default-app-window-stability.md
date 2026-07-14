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
- [x] Coalesce concurrent launch, restore, and pending-launch requests for the
      same app so MainActor reentrancy cannot send duplicate Windows launches.
- [x] Cover the launch race with a delayed-service regression test and verify a
      failed shared launch is removed before the next retry.
- [x] Serialize same-app guest launches and make normal host launches request
      existing-window reuse, so concurrent clients cannot both create Notepad.
- [x] Remove request WebSockets from the guest event-broadcast set after their
      first request, preventing unrelated window/frame events from occupying
      `app.launch` reply slots and triggering retries.
- [x] Restart the guest agent through a `RunLevel Limited` interactive task
      after elevated firewall repair, so launched Windows apps remain under the
      signed-in user's normal integrity level.
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
- [x] On July 14, 2026, deploy the refreshed Windows Arm agent, observe
  `standardUserAgentStartRequested` followed by
  `guestAgentHealthSucceeded=True`, and confirm a standard-user command can
  terminate the agent-launched Notepad process without access denied.
- [x] Configure the managed test guest's Notepad startup policy to begin a new
  session instead of replaying prior unsaved tabs, then visually confirm one
  guest Notepad window.
- [x] Run `app-window-proof` twice against the live guest and confirm both calls
  reuse PID `9328` and HWND `hwnd:000602DC` with a 600 x 393 PNG frame.
- [x] Run `mvp-proof --require-proved` on the same HWND and confirm mouse,
  keyboard, clipboard, and post-input frame evidence with `status=proved`.

## Follow-up

- [ ] Design an explicit multi-document action and restore ordering before
  allowing more than one mirrored window for the same app in the normal path.
- [ ] Keep guest-agent recovery separate from window creation: an unavailable
  agent must leave the launcher recoverable, not create placeholder windows.
- [ ] Productize the managed-guest Notepad startup policy without editing the
  private packaged-app `settings.dat` hive; the current live proof used the
  supported Notepad settings UI.
- [ ] Replace fixed Run/UAC timing in `qemu-install-agent` with a bounded,
  screenshot-backed readiness/retry flow so a busy post-boot desktop cannot
  consume the install command or approval keys.
