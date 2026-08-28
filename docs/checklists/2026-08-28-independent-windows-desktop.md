# Independent Windows Desktop Checklist

Goal: make the full Windows desktop appear as a first-class macOS window instead of a screen nested inside the Veil launcher.

- [x] Reuse the existing loopback RFB display and QMP input path.
- [x] Open one independent `Windows 11` macOS window for QEMU.
- [x] Reuse and front the same window on repeated display commands.
- [x] Support resize, minimize, close, and native macOS full screen.
- [x] Close the desktop window when Windows stops.
- [x] Expose the display command for captured QEMU surfaces, not only raw Cocoa display builds.
- [x] Route the launcher display button and app/menu-bar commands to the independent window.
- [x] Preserve the separate app-first HWND windows and launcher.
- [x] Verify the signed installed app against a live `127.0.0.1:5900` Windows display.
- [ ] Add dynamic guest-resolution renegotiation when the desktop window changes size.
- [ ] Add a lower-latency accelerated renderer; current RFB presentation is not GPU-accelerated VMware/Parallels parity.
