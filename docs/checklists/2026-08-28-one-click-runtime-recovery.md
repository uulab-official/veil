# One-Click Runtime Recovery Checklist

Goal: keep the normal product path app-first. When an existing QEMU/HVF Windows
session loses both its RFB and guest-agent transports, one **Open Notepad** action
must recover the runtime and open the HWND as a macOS window without exposing a VM
manager workflow.

## P0 launch path

- [x] Keep a bootstrap catalog for Notepad, Calculator, and Paint while the live
  guest catalog is reconnecting.
- [x] Keep app launch commands enabled during a recoverable display/agent outage.
- [x] Prefer **Open Notepad** over **Stop Windows** as the installed-runtime hero.
- [x] Queue the selected app from one user action.
- [x] Wait once for the guest agent before intervening.
- [x] For a known QEMU session, run one bounded QMP stop/continue transport recovery.
- [x] Wait again and fulfill the queued launch automatically.
- [x] Fall back to the existing bounded attached-media agent repair only when runtime
  recovery does not restore the connection.
- [x] Prevent duplicate clicks from creating parallel recovery/launch tasks.

## Live verification (2026-08-28)

- [x] Reproduced the failure with QMP alive while RFB and `ws://127.0.0.1:18444`
  timed out; QEMU was consuming approximately 127% CPU.
- [x] Started recovery from the signed Veil app with one app-open command.
- [x] Confirmed QEMU returned to `running` and approximately 32% CPU after recovery.
- [x] Confirmed RFB returned a non-blank 800×600 Windows desktop frame.
- [x] Confirmed Veil Agent 0.1.0 reconnected on the first post-recovery probe.
- [x] Confirmed Notepad opened automatically as HWND `000200C6` in a macOS window.
- [x] Confirmed live frame streaming at 600×393 in the host window.
- [x] Passed `mvp-proof --require-proved`: initial frame 3ms and post-input frame
  710ms, both inside the 1,000ms fresh-frame budget; mouse, keyboard, text, and
  clipboard paths were exercised.

## Production gaps that remain

- [ ] Prove and tune accelerated 3D graphics. Current QEMU/HVF + virtio-gpu work is
  not equivalent to Parallels GPU acceleration and must not be marketed as such.
- [ ] Complete Windows sparse-package identity; the current guest reports the
  Windows SDK `MakeAppx.exe` is unavailable.
- [ ] Complete notification-listener consent after package identity is ready.
- [ ] Replace the non-migratable NVMe storage configuration before claiming VM
  suspend/resume support.
- [ ] Add longer soak coverage for repeated sleep/wake, network interruption,
  resolution changes, and multiple concurrent Windows app windows.
