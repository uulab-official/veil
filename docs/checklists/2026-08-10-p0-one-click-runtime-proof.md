# P0 One-Click Windows App Runtime Proof

Date: 2026-08-27
Tested implementation commit: `b8eea9f` (`fix: prioritize live Windows app windows over stale display`)
Latest verification commit: `b8eea9f` (`fix: prioritize live Windows app windows over stale display`)
Branch: `codex/ui-display-state`

Purpose: keep the host-side implementation result separate from proof that a real
Windows 11 Arm guest booted, connected, and rendered an app window. This record
does not claim Parallels-level GPU acceleration.

## Deterministic gates

- [x] Swift host: isolated `swift test --disable-sandbox --package-path apps/mac-host` with a temporary `CFFIXED_USER_HOME`/`HOME` and unreachable agent endpoint — **728 tests / 62 suites passed**.
- [x] Windows agent: `dotnet test apps/windows-agent/tests/VeilAgent.Tests/VeilAgent.Tests.csproj` with Veil's local .NET 8 toolchain — **122 tests passed**.
- [x] Node protocol and harness packages: `./script/test_all.sh --skip-windows-agent` — **30 packages passed**.
- [x] Swift build and macOS app bundle/sign/launch contract passed through `script/test_all.sh --skip-windows-agent`.
- [x] Install, guarded replace, quarantine cleanup, uninstall, user-data preservation, reinstall, and first-window lifecycle checks passed.
- [x] Focused P0 launch, display-policy, and window handoff tests passed.
- [x] Clean post-change `./script/test_all.sh --skip-windows-agent` passed: isolated Swift host tests, 30 Node packages, signed app launch, and install/uninstall lifecycle.
- [x] `qemu-doctor` blocks a stale installed flag when the configured Windows system disk is missing.
- [x] Managed QEMU and `swtpm` runtime discovery works for Finder-launched sessions without a shell `PATH`.
- [x] CLI QEMU launches use a parent supervisor and record the real backend PID, so the UTM parent-watchdog cannot kill the VM when `veil-vmctl` exits.
- [x] Native-display requests fail before TPM/QEMU startup when the selected QEMU does not expose Cocoa, with an actionable embedded-VNC fallback.

The full no-skip gate now discovers the bundled local .NET 8 toolchain
automatically:

```bash
./script/test_all.sh
```

For another local installation, set `VEIL_DOTNET_TOOLCHAIN_DIR` to the folder
that contains `dotnet` before running the gate.

## Live Windows gates

- [x] Fresh boot-safe QEMU/HVF launch reaches the Windows 11 Arm installer.
- [x] Embedded VNC surface returns a real **800 x 600** framebuffer and remains attached after the CLI exits.
- [x] The visible launch path reaches the Korean Windows Setup screen after the initial Windows logo/loading phase.
- [x] Guest-agent health through `ws://127.0.0.1:18444`; `guest-agent-wait --wait-seconds 30` connected as Windows ARM64 user `Veil`, agent `0.1.0`.
- [x] `mvp-proof --app-id winapp_notepad --require-proved` passed at `2026-08-27T08:46:54Z`: HWND `0001034C`, focused, 600 x 393 frame, initial **5 ms**, post-input **697 ms**, keyboard/mouse/clipboard all recorded.
- [x] `multi-app-proof --app-ids winapp_notepad,winapp_calculator,winapp_paint --require-complete` passed for all **3/3** apps; slowest measured frame latency **688 ms**, within the 1,000 ms budget.
- [x] One-click from a stopped VM starts QEMU, waits for the guest agent, and opens Notepad as one independent macOS window.
- [x] One Notepad tile click opens exactly one independent macOS standard window (`hwnd:000103A2` observed; no embedded desktop surface).
- [x] Protocol-level initial and post-input frames prove mouse, keyboard, and clipboard behavior.
- [x] Normal app launch never exposes a nested Windows desktop; the native window showed the Korean Notepad surface directly.
- [x] Repeated frame updates preserve the independent window while fresh capture frames advance; the resized window continued to show a complete 600 x 393 guest frame.
- [x] Host-shell zoom/restore, resize, focus, and close cycle is proven on a real independent macOS window; closing returned to the launcher and quieted QEMU.

### Current live prerequisite result

`veil-vmctl qemu-doctor --json` now reports `overallState: ready` on the
configured Apple Silicon Mac:

- Windows profile, Microsoft installer ISO, VeilAutoInstall support media,
  writable system disk, Arm UEFI variables, TPM 2.0, HVF, and the loopback
  shared-folder forward all pass.
- Veil discovers its managed QEMU and `swtpm` runtime from Application Support,
  so a Finder-launched app does not depend on a terminal environment.
- Secure Boot remains a warning until a live setup run proves the requirement;
  the readiness report does not overstate that capability.
- The current UTM QEMU build exposes `none`, `egl-headless`, `spice-app`, and
  `dbus`, but not Cocoa. `qemu-start --native-display` therefore exits before
  creating TPM/QEMU processes and directs the user to the embedded VNC console.

The real `qemu-start --wait-seconds 15` path was observed to keep its backend
alive after `veil-vmctl` returned. The subsequent VNC smoke captured a Windows
11 Korean Setup screen, and the same installed guest later connected through
the agent channel. The `mvp-proof` and `multi-app-proof` artifacts remain in
the local `~/Library/Application Support/Veil/Diagnostics` directory and are
not committed to Git. Together with the live host-shell exercise above, this
proves the VM boot/display transport, protocol-level Windows app loop, and the
initial independent macOS HWND window path; it does not prove the complete
production feature set or Parallels-level graphics support.

The host status model now treats a healthy live guest agent as authoritative for
continuing the app flow even when the headless VNC console preview is stale or
unavailable. The host shell has now been exercised with a real HWND mirror as an
independent macOS window. The release gate remains open for package identity,
notifications, and GPU capability work; the UI does not call the product
Parallels-equivalent or release-ready from an agent connection alone.

## Next live verification sequence

1. Repeat the first-frame, input, clipboard, focus, resize, and repeated-launch
   checks from the host-shell surface after a fresh VM restart.
2. Prepare the signed sparse package identity, then run the real borderless
   Windows Graphics Capture and notification consent proofs.
3. Re-run the clean full script gate with the VM state isolated from test
   Application Support before calling the runtime production-ready.
4. Record only observed live evidence, measured frame latencies, and tool/build
   identities. Keep screenshots, Windows media, clipboard content, and local
   user paths outside Git.

## Status

**VM boot/display, protocol-level app-runtime proof, and the first host-shell
independent-window proof passed.** The live agent, Notepad/Calculator/Paint HWND
tracking, frame delivery, input, clipboard, native window presentation, and the
initial resize/focus/close flow are verified. Independent package identity,
notification consent, repeated restart recovery, and GPU acceleration remain
unproven. Veil makes no Parallels-level GPU claim.
