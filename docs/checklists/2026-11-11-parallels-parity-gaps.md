# Parallels Parity Gaps

Date: 2026-11-11

This inventory compares Veil with Parallels Desktop's user-facing features. It comes from the code and
the docs, corrected by what was measured on the live Windows 11 Arm guest during 2026-11-09…11.
"Live" means checked on that guest; "unit" means covered by tests only.

| # | Feature | Status | Notes |
|---|---|---|---|
| 1 | Coherence: one Mac window per app, desktop hidden | Partial (live) | Windows come from the guest framebuffer (`window.layout`, `window.crop.set`, `window.move.request`). Every app window on the Windows desktop now gets a Mac window, whoever opened it (`capabilities.desktopWindows`, `window.list.request`). Live, 2026-11-12: Notepad and Paint left open in Windows and Character Map appeared as three Mac windows after a Veil relaunch, with no helper windows, and Character Map at its own 477 x 430. Not done: a window another one covers is still shown from captured frames every few seconds, and the Windows taskbar was visible in the guest during this check. The Dock menu and the menu bar menu have a Windows Start Menu; Character Map was opened from it live, File Explorer and UWP apps were not tried. |
| 2 | Apps in Dock, Launchpad, Applications; "Open with" | Implemented (live, partly) | Opening a Windows app writes a signed launcher to `~/Applications/Veil Apps` (`09dfe151`). Live: Notepad's launcher was created, passes `codesign --verify --strict`, and is listed by Launch Services for `.txt` files. Opening a file through it was not tried, because that brings Veil forward. |
| 3 | Clipboard and drag and drop | Implemented | Text and images go both ways. Files go Mac to Windows by drop or paste, and Windows to the Mac by copying in Explorer (CF_HDROP through the shared folder to Downloads). Drops travel as base64. |
| 4 | Shared folders | Implemented (live) | Windows to Mac: `C:\VeilShared` over SMB. Mac to Windows, as UTM does for Windows guests: a folder chosen with Share a Mac Folder with Windows is served over WebDAV on 127.0.0.1 under a random token and mapped as `Mac (M:)` (`host.folder.mount.request`). Live: Explorer listed the test folder's file and subfolder; turning sharing off removed the drive and closed the port. Writing from Windows is unit-tested only. |
| 5 | Retina | Implemented (live, agent side) | With Retina resolution, the default once the agent reports `displayScale`, the apps view runs the guest display at twice the screen in points and Windows at 200% (`display.scale.request`). About 5% frame-rate cost. See `2026-11-11-retina-guest-scale.md`. |
| 6 | Keyboard and IME | Implemented (live, partly) | Keys reach Windows by position and the Windows IME composes, as in UTM and Parallels; 입니다 + Enter came out right through both QEMU and the agent. Switching the macOS input source also presses the Windows Hangul key; right Command switches Windows alone. Composing on the Mac and rewriting the guest's text swapped syllables and was dropped. Typing on the Mac keyboard is not yet confirmed by the user. |
| 7 | Trackpad | Implemented (unit) | Smooth scrolling works. Pinch is sent as Ctrl+wheel zoom and the three-finger page swipe as Browser Back/Forward. A two-finger horizontal swipe stays a horizontal scroll, and rotation has no Windows mapping. Not yet checked on the live guest: that needs real trackpad input. |
| 8 | Printers, camera, USB, audio | Partial | USB works. The printer bridge is research only. Camera is missing. |
| 9 | Suspend, idle pause, snapshots, shutdown | Implemented | Live: Stop now finishes when Windows shuts down without powering off (`1c3713b3`). Snapshots need qcow2. |
| 10 | Notifications | Implemented (unit) | Delivery on the live guest is unchecked. |
| 11 | Network | Partial | NAT and port forwarding work. Bridged networking needs Apple's vmnet entitlement. |
| 12 | Time, battery, dark mode sync | Implemented (live, partly) | Time: `time.sync.request` on agent connect, Mac wake, and session resume; correcting the clock needs the elevated-install `VeilTimeSync` task. Dark mode: `appearance.set.request`, on by default. Battery: not feasible, because QEMU `virt` has no ACPI battery (`docs/research/guest-host-state-sync.md`). Live, with agent `0.1.0+92b4061b37aa`: the agent reports `timeSync` and `appearanceSync`; with the Mac in dark mode Windows was already dark (`changed: false`), and the guest clock was 159 ms from the Mac's. Correcting a skewed clock and switching while Veil runs are unchecked. |
| 13 | DirectX acceleration | Missing (experiment measured) | Software rendering (WARP): Paint at 23.5 fps, DWM presents 40.6 ms apart. With Triton on the same VM: 72 fps and 13.6 ms (the 75 Hz cap). Not shippable yet: with the driver installed Windows does not shut down, and the default runtime shows no display. The VM was restored to `snapshots/pre-triton-20261111-1506`; the Triton disk is kept as `snapshots/post-triton-20261111-1617`. |
| 14 | Dynamic memory | Blocked (live) | The host side is done, but virtio-win 0.1.302's ARM64 Balloon driver gives wrong buffer addresses. Reported as virtio-win/kvm-guest-drivers-windows#1719. |

## Order of work

1. Hide the Windows taskbar while app windows are shown (gap 1). This slice.
2. Set Windows to 200% on Retina so text is sharp (gap 5).
3. Per-app launchers and "Open with" (gap 2).
4. Files from Windows to the Mac (gap 3).
5. GPU acceleration (gap 13). Triton session.
6. Sync dark mode, time after resume, and battery state (gap 12).

## Found on the live guest on 2026-11-12

- **Typed commands are not safe with apps open.** The tools update and the agent repair type into the Windows
  Run dialog through QEMU: a click at a fixed place, Ctrl+A, then the command. With Notepad and Paint open,
  one run replaced the text of an open Notepad document and changed Paint's tool. The text was restored with
  undo. The host now refuses to type while Windows has app windows open
  (`AppRuntimeBooterError.windowsAppsAreOpen`). The update should be run by the agent itself, from the tools
  disc, with no typing. That is not built yet.
- **Maintenance closed windows by itself.** A window covered by another one looked stale and was closed and
  reopened every few seconds. Maintenance that runs by itself no longer closes a window.
- **`input.text` lost characters.** A command typed through the agent into Command Prompt arrived without
  seven of its characters while the host was also raising another window. Not investigated.
- **The guest clock is 65 minutes off.** `time.sync.request` fails with `install-time-sync-task-elevated`.

