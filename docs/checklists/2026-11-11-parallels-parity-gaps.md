# Parallels Parity Gaps

Date: 2026-11-11

This inventory compares Veil with Parallels Desktop's user-facing features. It comes from the code and
the docs, corrected by what was measured on the live Windows 11 Arm guest during 2026-11-09…11.
"Live" means checked on that guest; "unit" means covered by tests only.

| # | Feature | Status | Notes |
|---|---|---|---|
| 1 | Coherence: one Mac window per app, desktop hidden | Partial (live) | Windows come from the guest framebuffer (`window.layout`, `window.crop.set`, `window.move.request`). The Windows taskbar still covers the bottom of the guest display and can cover windows there, so this slice hides it. There is no Start menu from the Mac. |
| 2 | Apps in Dock, Launchpad, Applications; "Open with" | Implemented (live, partly) | Opening a Windows app writes a signed launcher to `~/Applications/Veil Apps` (`09dfe151`). Live: Notepad's launcher was created, passes `codesign --verify --strict`, and is listed by Launch Services for `.txt` files. Opening a file through it was not tried, because that brings Veil forward. |
| 3 | Clipboard and drag and drop | Partial | Text and images go both ways. Files go Mac to Windows only, and drops travel as base64. |
| 4 | Shared folders | Partial | `C:\VeilShared` is available on the Mac over SMB. Mac folders inside Windows are not. |
| 5 | Retina | Implemented (live, agent side) | With Retina resolution, the default once the agent reports `displayScale`, the apps view runs the guest display at twice the screen in points and Windows at 200% (`display.scale.request`). About 5% frame-rate cost. See `2026-11-11-retina-guest-scale.md`. |
| 6 | Keyboard and IME | Implemented (unit) | Korean input on the live guest is still unchecked. |
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
