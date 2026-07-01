# App Icon And Console Reopen Checklist

Goal: make the macOS shell feel more like a real virtualization app and make the Windows setup console recoverable.

- [x] Generate a local `.icns` app icon during bundle packaging.
- [x] Add `CFBundleIconFile` to the generated app `Info.plist`.
- [x] Verify icon generation without launching or killing the active VM.
- [x] Keep the VM console presenter reusable after the console window is closed.
- [x] Add Show Console to the toolbar while the VM is running or starting.
- [x] Add Console to VM Quick Actions.
- [x] Document that the current Windows installer display path is still experimental.

Next:

- [ ] Add visible last-boot/last-console diagnostics in the VM Runtime screen.
- [ ] Prove or replace the Apple Virtio graphics path for Windows installer display.
