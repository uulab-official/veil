# Parallels Parity Gaps

Date: 2026-11-11

This inventory compares Veil with Parallels Desktop's user-facing features. It comes from the code and
the docs, corrected by what was measured on the live Windows 11 Arm guest during 2026-11-09…11.
"Live" means checked on that guest; "unit" means covered by tests only.

| # | Feature | Status | Notes |
|---|---|---|---|
| 1 | Coherence: one Mac window per app, desktop hidden | Partial (live) | Windows come from the guest framebuffer (`window.layout`, `window.crop.set`, `window.move.request`). The Windows taskbar still covers the bottom of the guest display and can cover windows there, so this slice hides it. There is no Start menu from the Mac. |
| 2 | Apps in Dock, Launchpad, Applications; "Open with" | Partial | Dock icons and the Dock menu exist. There are no per-app `.app` launchers and no `CFBundleDocumentTypes`. |
| 3 | Clipboard and drag and drop | Partial | Text and images go both ways. Files go Mac to Windows only, and drops travel as base64. |
| 4 | Shared folders | Partial | `C:\VeilShared` is available on the Mac over SMB. Mac folders inside Windows are not. |
| 5 | Retina | Implemented (live, agent side) | With Retina resolution, the default once the agent reports `displayScale`, the apps view runs the guest display at twice the screen in points and Windows at 200% (`display.scale.request`). About 5% frame-rate cost. See `2026-11-11-retina-guest-scale.md`. |
| 6 | Keyboard and IME | Implemented (unit) | Korean input on the live guest is still unchecked. |
| 7 | Trackpad | Partial | Smooth scrolling works. There are no pinch, swipe, or rotate gestures. |
| 8 | Printers, camera, USB, audio | Partial | USB works. The printer bridge is research only. Camera is missing. |
| 9 | Suspend, idle pause, snapshots, shutdown | Implemented | Live: Stop now finishes when Windows shuts down without powering off (`1c3713b3`). Snapshots need qcow2. |
| 10 | Notifications | Implemented (unit) | Delivery on the live guest is unchecked. |
| 11 | Network | Partial | NAT and port forwarding work. Bridged networking needs Apple's vmnet entitlement. |
| 12 | Time, battery, dark mode sync | Missing | Only `-rtc base=localtime` exists. |
| 13 | DirectX acceleration | Missing | Software rendering, measured at 27–46 fps. The Triton experiment is in a separate session. |
| 14 | Dynamic memory | Blocked (live) | The host side is done, but virtio-win 0.1.302's ARM64 Balloon driver gives wrong buffer addresses. Reported as virtio-win/kvm-guest-drivers-windows#1719. |

## Order of work

1. Hide the Windows taskbar while app windows are shown (gap 1). This slice.
2. Set Windows to 200% on Retina so text is sharp (gap 5).
3. Per-app launchers and "Open with" (gap 2).
4. Files from Windows to the Mac (gap 3).
5. GPU acceleration (gap 13). Triton session.
6. Sync dark mode, time after resume, and battery state (gap 12).
