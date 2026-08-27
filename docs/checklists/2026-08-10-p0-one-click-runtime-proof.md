# P0 One-Click Windows App Runtime Proof

Date: 2026-08-27
Tested commit: `bdef7f7` (`feat: advance production Windows app runtime`)
Branch: `codex/ui-display-state`

Purpose: keep the host-side implementation result separate from proof that a real
Windows 11 Arm guest booted, connected, and rendered an app window. This record
does not claim Parallels-level GPU acceleration.

## Deterministic gates

- [x] Swift host: `swift test --disable-sandbox --package-path apps/mac-host` — **719 tests / 62 suites passed**.
- [x] Windows agent: `dotnet test apps/windows-agent/tests/VeilAgent.Tests/VeilAgent.Tests.csproj` with Veil's local .NET 8 toolchain — **122 tests passed**.
- [x] Node protocol and harness packages: `./script/test_all.sh --skip-windows-agent` — **30 packages passed**.
- [x] Swift build and macOS app bundle/sign/launch contract passed through `script/test_all.sh --skip-windows-agent`.
- [x] Install, guarded replace, quarantine cleanup, uninstall, user-data preservation, reinstall, and first-window lifecycle checks passed.
- [x] Focused P0 launch, display-policy, and window handoff tests passed.

The full no-skip gate now discovers the bundled local .NET 8 toolchain
automatically:

```bash
./script/test_all.sh
```

For another local installation, set `VEIL_DOTNET_TOOLCHAIN_DIR` to the folder
that contains `dotnet` before running the gate.

## Live Windows gates

- [ ] Fresh boot-safe QEMU/HVF launch.
- [ ] Guest-agent health through `ws://127.0.0.1:18444`.
- [ ] One Notepad tile click opens exactly one independent macOS window.
- [ ] Initial and post-input frames prove mouse, keyboard, and clipboard behavior.
- [ ] Normal app launch never exposes a nested Windows desktop.
- [ ] Repeated frame updates preserve window size, position, and focus.

### Current live prerequisite result

`veil-vmctl qemu-doctor --json` ran successfully but reported `overallState:
blocked`:

- Windows profile, installer/support media, UEFI, HVF plan, and shared-folder
  contracts passed.
- The writable Windows system disk is missing.
- `qemu-system-aarch64` is not installed or configured.
- `swtpm` is not installed or configured.
- Secure Boot is only a warning until a live setup smoke passes.

The attempted `qemu-start` and `mvp-proof --require-proved` runs therefore did
not produce live Windows evidence; the forwarded guest-agent endpoint was not
available. These gates must remain unchecked.

## Next live verification sequence

1. Install a supported local QEMU build with `qemu-system-aarch64` and `swtpm`.
2. Use the Microsoft-provided Windows 11 Arm ISO with `veil-vmctl prepare` to
   create the local writable system disk; do not commit the ISO or disk image.
3. Run `qemu-smoke`, boot to Windows Setup/Desktop, and complete the guest
   agent installation and health check.
4. Run `mvp-proof --json --app-id winapp_notepad --require-proved`, then exercise
   the one-click path from the built Veil app.
5. Record only observed live evidence, measured frame latencies, and tool/build
   identities. Keep screenshots, Windows media, clipboard content, and local
   user paths outside Git.

## Status

**Implemented, live verification pending.** The host-side P0 one-click flow is
covered by deterministic tests and release lifecycle gates, but this commit is
not a claim that the real Windows runtime or GPU acceleration is production
ready.
