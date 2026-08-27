# P0 One-Click Windows App Runtime Proof

Date: 2026-08-27
Tested implementation: working tree for the next QEMU/display hardening commit.
Latest baseline verification commit: `2c5eb11` (`docs: record current readiness gate counts`)
Branch: `codex/ui-display-state`

Purpose: keep the host-side implementation result separate from proof that a real
Windows 11 Arm guest booted, connected, and rendered an app window. This record
does not claim Parallels-level GPU acceleration.

## Deterministic gates

- [x] Swift host: `swift test --disable-sandbox --package-path apps/mac-host` — **727 tests / 62 suites passed**.
- [x] Windows agent: `dotnet test apps/windows-agent/tests/VeilAgent.Tests/VeilAgent.Tests.csproj` with Veil's local .NET 8 toolchain — **122 tests passed**.
- [x] Node protocol and harness packages: `./script/test_all.sh --skip-windows-agent` — **30 packages passed**.
- [x] Swift build and macOS app bundle/sign/launch contract passed through `script/test_all.sh --skip-windows-agent`.
- [x] Install, guarded replace, quarantine cleanup, uninstall, user-data preservation, reinstall, and first-window lifecycle checks passed.
- [x] Focused P0 launch, display-policy, and window handoff tests passed.
- [x] Bare `./script/test_all.sh` passed with Swift, Windows agent, Node, and macOS lifecycle gates.
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
- [ ] Guest-agent health through `ws://127.0.0.1:18444`.
- [ ] One Notepad tile click opens exactly one independent macOS window.
- [ ] Initial and post-input frames prove mouse, keyboard, and clipboard behavior.
- [ ] Normal app launch never exposes a nested Windows desktop.
- [ ] Repeated frame updates preserve window size, position, and focus.

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
11 Korean Setup screen. The screenshot and logs remain in the local
`~/Library/Application Support/Veil/Diagnostics/QEMU Launch` directory and are
not committed to Git. This proves VM boot and display transport only; it does
not prove unattended setup completion, guest-agent health, Notepad launch, or
first mirrored HWND frame.

## Next live verification sequence

1. Continue the install from the embedded VNC console and complete Windows
   Setup; the current evidence stops at the installer screen.
2. Run `veil-vmctl qemu-install-agent --json` after the first desktop login and
   verify `ws://127.0.0.1:18444` health plus the installed agent evidence.
3. Run `mvp-proof --json --app-id winapp_notepad --require-proved`, then exercise
   the one-click path from the built Veil app.
4. Add measured first-frame, input, clipboard, focus, resize, and repeated
   launch evidence before calling the runtime production-ready.
5. Record only observed live evidence, measured frame latencies, and tool/build
   identities. Keep screenshots, Windows media, clipboard content, and local
   user paths outside Git.

## Status

**VM boot/display proof passed; app-runtime proof is still open.** The host-side
P0 one-click flow is covered by deterministic tests and release lifecycle gates,
and the real managed QEMU path now reaches Windows Setup. Guest-agent,
Notepad/HWND mirroring, input/clipboard, and GPU acceleration remain unproven.
