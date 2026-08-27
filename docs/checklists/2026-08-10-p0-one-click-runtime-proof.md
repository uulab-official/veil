# P0 One-Click Windows App Runtime Proof

Date: 2026-08-27
Tested implementation commit: `3121642` (`fix: align Windows app readiness with live agent`)
Latest verification commit: `3121642` (`fix: align Windows app readiness with live agent`)
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
- [ ] A clean post-change `./script/test_all.sh` run remains to be repeated outside the live VM state; the isolated Swift gate above is the accepted current host result.
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
- [x] `mvp-proof --app-id winapp_notepad --require-proved` passed at `2026-08-27T08:04:59Z`: HWND `00020386`, focused, 354 x 162 frame, initial **5 ms**, post-input **677 ms**, keyboard/mouse/clipboard all recorded.
- [x] `multi-app-proof --app-ids winapp_notepad,winapp_calculator,winapp_paint --require-complete` passed for all **3/3** apps; slowest measured frame latency **688 ms**, within the 1,000 ms budget.
- [ ] One Notepad tile click opens exactly one independent macOS window.
- [x] Protocol-level initial and post-input frames prove mouse, keyboard, and clipboard behavior.
- [ ] Normal app launch never exposes a nested Windows desktop.
- [ ] Repeated frame updates preserve window size, position, and focus.
- [ ] Host-shell resize/focus/close cycle is proven on a real independent macOS window.

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
not committed to Git. This proves the VM boot/display transport and the
protocol-level Windows app loop; it does not yet prove that the built host shell
renders the HWND as one independent macOS window or that resize/focus recovery
is production-ready.

The host status model now treats a healthy live guest agent as authoritative for
continuing the app flow even when the headless VNC console preview is stale or
unavailable. It still keeps the release gate open until a real host-side HWND
mirror exists, so the UI cannot call the product release-ready from an agent
connection alone.

## Next live verification sequence

1. Exercise the built host shell from the live connected state and capture one
   independent macOS Notepad window with launcher hiding, focus, resize, and
   close/restore behavior.
2. Repeat the first-frame, input, clipboard, focus, resize, and repeated-launch
   checks from that host-shell surface rather than only from CLI protocol proof.
3. Prepare the signed sparse package identity, then run the real borderless
   Windows Graphics Capture and notification consent proofs.
4. Re-run the clean full script gate with the VM state isolated from test
   Application Support before calling the runtime production-ready.
5. Record only observed live evidence, measured frame latencies, and tool/build
   identities. Keep screenshots, Windows media, clipboard content, and local
   user paths outside Git.

## Status

**VM boot/display and protocol-level app-runtime proof passed; host-shell proof
is still open.** The live agent, Notepad/Calculator/Paint HWND tracking, frame
delivery, input, and clipboard loop are verified. Independent macOS window
presentation, resize/focus recovery, signed package identity, notifications,
and GPU acceleration remain unproven. Veil makes no Parallels-level GPU claim.
