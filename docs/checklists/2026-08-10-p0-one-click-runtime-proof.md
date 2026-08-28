# P0 One-Click Windows App Runtime Proof

Date: 2026-08-28
Tested implementation commit: `36f6319` (`feat: recover stalled Windows app launches automatically`)
Latest verification: installed `/Applications/Veil.app` build on `2026-08-28`
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
- [x] QMP replies with CRLF line endings are normalized before parsing, so a live QEMU control socket is not misreported as silent.
- [x] The host disables suspend/resume when the live QEMU command line uses the non-migratable NVMe system device instead of offering a control that QEMU will reject.
- [x] Sparse-package preparation resolves `MakeAppx.exe` and `SignTool.exe` before creating a development certificate, and records a structured `prerequisiteMissing` result when the Windows SDK is absent.
- [x] The main launcher ignores an empty AppKit-restored window state and presents deterministically; the signed app launch contract passed five consecutive post-fix runs.
- [x] If SwiftUI does not materialize the main scene during a Finder/Dock launch, an AppKit fallback creates the same branded launcher content with one stable window, production minimum bounds, and a deterministic reopen path.
- [x] QEMU runtime recovery pauses and resumes only a machine first confirmed as running, verifies both transitions, and never resumes an intentionally paused VM; five focused recovery tests pass.
- [x] The embedded RFB display retries a dropped loopback connection with bounded backoff while rejecting stale worker callbacks from older connections.

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
- [x] `mvp-proof --app-id winapp_notepad --require-proved` passed at `2026-08-28T00:05:02Z`: HWND `000200C6`, focused, 600 x 393 frame, initial **3 ms**, post-input **686 ms**, keyboard/mouse/clipboard all recorded.
- [x] `multi-app-proof --app-ids winapp_notepad,winapp_calculator,winapp_paint --require-complete` passed at `2026-08-28T00:05:20Z` for all **3/3** apps; slowest measured frame latency **710 ms**, within the 1,000 ms budget.
- [x] One-click from a stopped VM starts QEMU, waits for the guest agent, and opens Notepad as one independent macOS window.
- [x] One Notepad tile click opens exactly one independent macOS standard window (`hwnd:000103A2` observed; no embedded desktop surface).
- [x] Protocol-level initial and post-input frames prove mouse, keyboard, and clipboard behavior.
- [x] Normal app launch never exposes a nested Windows desktop; the native window showed the Korean Notepad surface directly.
- [x] Repeated frame updates preserve the independent window while fresh capture frames advance; the resized window continued to show a complete 600 x 393 guest frame.
- [x] Host-shell zoom/restore, resize, focus, and close cycle is proven on a real independent macOS window; closing returned to the launcher and quieted QEMU.
- [x] Mirrored-window resize negotiates `capabilities.windowResize`, sends one bounded `window.resize.request` after the macOS gesture, applies the size to the Windows HWND, and waits for the authoritative `window.updated`/key-frame path.
- [x] A deliberately stale long-lived session with QMP alive, RFB unavailable, and the guest-agent forward unavailable recovered from the one-click app lifecycle without a force stop; Notepad then appeared as the only normal surface.
- [x] Commit `36f6319` was installed at `/Applications/Veil.app`; relaunch restored the existing Notepad HWND directly as an independent 600 x 393 macOS window with fresh frames (36 frames observed, latest interval 308 ms) while the launcher stayed hidden.
- [x] The installed app's one-click command reused HWND `000200C6` instead of creating a duplicate and restarted a fresh frame subscription (frame 276 observed at 600 x 393, latest interval 347 ms).

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

### Session persistence safety gate

The live QEMU session was rechecked on `2026-08-27` after the QMP parser fix:

- QMP `query-status` returned `running: true` through `/tmp/vq-15D244F0.qmp.sock`.
- `veil-vmctl vm-session-status --json` returned `canSuspend: false` and
  `persistence.mode: unsupported` because the active system disk is attached as
  `-device nvme,...`.
- A direct suspend attempt reached QEMU but was rejected with
  `State blocked by non-migratable device '0000:00:02.0/nvme'`.

This is now an explicit capability gate: Veil will stop Windows normally rather
than claim that the user's session was persisted. Enabling suspend requires a
separately validated migratable storage-device configuration; changing the
shipping Windows disk attachment without a boot proof is not safe.

### Long-lived runtime liveness incident

During the same verification, the existing QEMU process had been running for
about 14 hours and temporarily stopped serving both RFB and the guest-agent
forward while QMP still answered `query-status`. Its CPU usage was observed near
119%, and `system_powerdown` did not complete within 30 seconds. A reversible QMP
`stop` followed by `cont` restored the RFB and agent paths; the subsequent display,
agent, and app proofs passed. This is recovery evidence, not a production
reliability claim. Commit `05b8d5f` now adds automatic stale-session detection and
a reversible QMP pause/resume recovery path after a previously live guest-agent
connection drops. Live fault-injection and long-duration recovery measurement
remain open.

The same failure was then exercised through the signed Veil app on commit
`36f6319`. Before the app action, QMP reported `running` while both RFB and
`ws://127.0.0.1:18444` timed out and the QEMU backend was observed near 127% CPU.
One **Open Notepad** command queued the app, waited for the agent, ran the bounded
QMP pause/resume recovery, waited again, and opened HWND `000200C6` automatically.
After recovery:

- QEMU remained `running` and was observed near 32% CPU.
- `qemu-display-smoke` returned a non-blank 800 x 600 recovery desktop.
- `guest-agent-wait` connected on its first post-recovery attempt as agent 0.1.0.
- The host presented the Korean Notepad surface as a fresh 600 x 393 independent
  macOS window; the embedded Windows desktop was not the normal app surface.
- A fresh `mvp-proof --require-proved` passed with a 3 ms initial frame and 710 ms
  post-input frame, including mouse, keyboard, text, and clipboard evidence.

This closes the controlled live stale-transport recovery item for the P0
one-click path. Repeated fault injection, longer soak durations, and behavior
when QMP itself is unavailable remain reliability work rather than P0 proof.

### Sparse package prerequisite gate

The real Windows guest remained connected during the `2026-08-27` sparse package
attempt, but package identity stayed `false`. The guest reported that
`MakeAppx.exe` was unavailable and the Windows SDK bin directory was missing.
Commit `f754be1` moves this check before development-certificate generation, so
the next retry produces an actionable `prerequisiteMissing` status instead of
leaving signing artifacts behind. The Windows 10/11 SDK still has to be
installed in the guest before package identity, borderless capture, and
notification-consent proofs can be completed.

### Launcher restoration and scene-materialization safety gate

The failed launch-contract report on `2026-08-28` showed a regular active app
with zero main windows. AppKit's log simultaneously reported persistent state
to restore, while `MainWindowChrome.showMainWindow()` ran before the SwiftUI
scene existed and therefore had no window to show. Commit `96bd368` disables
AppKit's empty launcher restoration; the main Veil scene now follows its
deterministic presented launch behavior, while mirrored Windows app restoration
continues through Veil's own `WindowRestoreIntentStore`. A later reproduction
showed that the SwiftUI scene can still be absent on a clean signed launch, so
`MainWindowChrome` now creates an AppKit fallback with the same `ContentView`
root, identifier, size constraints, transparent titlebar, and single-window
deduplication. The complete gate and install/reinstall lifecycle now cover both
scene materialization and the fallback path.

## Next live verification sequence

1. Run repeated RFB/agent fault injection and multi-hour soak measurements,
   including the separate case where QMP itself is unavailable. The single
   controlled stale-transport recovery is now live-proved.
2. Install the Windows 10/11 SDK in the guest, retry sparse package preparation,
   and verify `packageIdentity=true` before running borderless Windows Graphics
   Capture and notification-consent proofs.
3. Validate a migratable system-storage configuration on a disposable Windows
   disk, then run one live suspend/resume round trip. Keep the current NVMe
   Windows disk unchanged until that boot and agent proof passes.
4. Re-run the clean full script gate with the VM state isolated from test
   Application Support before calling the runtime production-ready.
5. Record only observed live evidence, measured frame latencies, and tool/build
   identities. Keep screenshots, Windows media, clipboard content, and local
   user paths outside Git.

## Status

**VM boot/display, protocol-level app-runtime proof, and the first host-shell
independent-window proof passed.** The live agent, Notepad/Calculator/Paint HWND
tracking, frame delivery, input, clipboard, native window presentation, and the
initial resize/focus/close flow are verified. QMP parsing, unsupported NVMe
suspend gating, and guarded automatic QEMU connection recovery are now hardened,
but a saved-session round trip is not enabled for the current machine. Independent
package identity, notification consent, repeated restart recovery, live
long-duration recovery, migratable suspend/resume, and GPU acceleration remain
unproven. Veil makes no Parallels-level GPU claim.
