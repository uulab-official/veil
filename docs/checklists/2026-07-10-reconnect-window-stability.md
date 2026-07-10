# Reconnect Window Stability Checklist

Goal: keep one Windows application feeling like one macOS window after the VM, guest agent, or host shell reconnects.

## Completed

- [x] Reproduce the duplicate mirror cascade on the live Windows 11 Arm VM before changing restore behavior.
- [x] Add the protocol-level `reuseExistingWindow` launch intent, defaulting to `false` for ordinary user launches.
- [x] Make reconnect restore request one existing HWND per app instead of reopening every persisted window count.
- [x] Have the Windows agent choose the focused existing matching HWND when available and silently track all matching existing HWNDs before discovery resumes.
- [x] Keep persisted per-app window counts for diagnostics without treating them as a replay queue.
- [x] Keep `VEIL_AUTO` attached as read-only guest support media after Windows is installed so current agent repairs and updates can be delivered without reattaching setup media.
- [x] Rebuild support media, restart the live QEMU/HVF VM, and reconnect the real Windows 11 Arm agent.
- [x] Prove a real Notepad HWND, initial frame, mouse input, keyboard input, host-to-guest clipboard, and post-input frame with `mvp-proof --require-proved`.
- [x] Launch the built host shell against the live VM and verify exactly one visible Veil Notepad mirror at 734 x 481 points.

## Remaining

- [ ] Keep tuning post-input frame latency so it consistently meets the fresh-frame target under live VM load.
- [ ] Exercise multiple intentional document windows and define their user-visible restore ordering without reviving duplicate-window behavior.
