# Frame Stream Liveness Verification — 2026-08-08

## Outcome

`PASS` for the deterministic integration slice: a successfully captured but visually unchanged Windows app frame can now skip PNG/base64 encoding, emit a payload-free liveness heartbeat, and keep the host stream healthy without changing the displayed image or its latency evidence.

This does **not** mark Veil production-ready. The production gate remains `BLOCKED` at 22/37 passing P0 items, with 15 unresolved P0 items and `releaseReady=false`.

## Scope

- Preserve the existing JSON `window.frame` full-PNG contract for changed frames.
- Add `window.frame.unchanged` across fixture, executable JavaScript validator, C# agent, Swift host, docs, and harness.
- Compare captured ARGB pixels before PNG encoding and base64 expansion.
- Sample active windows at 33 ms and back off idle windows to 250 ms after 15 unchanged captures.
- Treat capture failure as missing evidence, never as an unchanged heartbeat.
- Separate displayed-frame age from stream-activity age on the host.
- Reset and release one retained pixel buffer per active HWND across restart, unsubscribe, cancellation, and unexpected exit.
- Keep binary frame transport and changed-region tiles out of this slice.

## Implementation Commits

- `f9ae5bd feat(protocol): add unchanged frame heartbeat`
- `4f555b5 perf(agent): suppress duplicate window frames`
- `f5cb3aa feat(agent): broadcast frame liveness heartbeats`
- `0776473 feat(host): track idle frame stream liveness`

## TDD Evidence

### Protocol

- [x] RED: `npm test --prefix packages/protocol` failed because `validateWindowFrameUnchanged` was not exported.
- [x] GREEN: 33/33 protocol tests passed.
- [x] Rejects a heartbeat carrying `encodedData`.
- [x] Rejects an invalid `capturedAt` timestamp.
- [x] Parses the stable `window.frame.unchanged.json` fixture.

### Windows Agent Capture and Cadence

- [x] RED: focused .NET build failed because `WindowFrameChangeTracker`, `WindowFrameStreamCadence`, and `WindowFrameCaptureResult` did not exist.
- [x] GREEN: 12 focused frame tests passed.
- [x] GREEN: 87/87 complete Windows Agent tests passed.
- [x] First pixel buffer is changed; an equal buffer is unchanged.
- [x] Changed bytes or dimensions produce a changed result.
- [x] Different HWNDs retain independent buffers.
- [x] Forgetting an HWND forces the next capture to be a real first frame.
- [x] Capture failure emits neither a frame nor a false heartbeat.
- [x] Unchanged capture emits one heartbeat without resending a frame.
- [x] Cadence enters idle only after the configured threshold and returns to active on the first change.
- [x] Long idle operation does not overflow the unchanged counter.

### Agent Server

- [x] RED: focused .NET test failed because `AgentReplies.SerializeUnchangedFrame` did not exist.
- [x] RED: Windows contract harness failed because the C# message constant and server wiring did not exist.
- [x] GREEN: deterministic serializer test passed and proves no `encodedData` field is emitted.
- [x] GREEN: 28/28 Windows Agent contract harness tests passed.
- [x] Previous stream generations remove only their own registration, preventing an old `finally` block from deleting a replacement stream.
- [x] Cancellation is rechecked after synchronous GDI capture before retained comparison state is updated.

### macOS Host

- [x] RED: focused Swift build failed because the event, activity fields, diagnostics, and receive path did not exist.
- [x] First GREEN attempt found an exhaustive app-shell switch omission; the liveness-only case was added as an intentional presentation no-op.
- [x] GREEN: 86/86 focused `HostDashboardModelTests` passed.
- [x] GREEN: 483/483 complete Swift tests across 29 suites passed.
- [x] A heartbeat after a real frame advances activity only.
- [x] A 10-second-old image with activity 250 ms ago remains healthy while reporting both ages honestly.
- [x] A heartbeat before the first real frame is ignored.
- [x] A heartbeat for an unknown HWND is ignored.
- [x] Protocol messages route to `.handledWindowFrameUnchanged` without refreshing the native window.
- [x] Frame timing saved before the new liveness keys decodes with activity equal to the latest real frame and heartbeat count zero.

## Complete Regression Gate

Executed at `2026-08-08 19:53–19:54 KST`:

```bash
VEIL_DOTNET_BIN="/Users/uulab/Library/Application Support/Veil/Toolchains/dotnet8/dotnet" ./script/test_all.sh
```

Result: `PASS` — `All requested Veil regression gates passed.`

- [x] Swift host: 483 tests, 29 suites.
- [x] Windows Agent: 87 tests.
- [x] Node packages: 25 packages.
- [x] macOS app bundle build and launch contract.
- [x] Temporary isolated Applications lifecycle: install, verified replace, quarantine cleanup, recoverable uninstall, support-data preservation, reinstall, and first-window launch.
- [x] `git diff --check` passed.
- [x] Branch was clean and synchronized before the evidence document was added.

The lifecycle test intentionally uses a temporary Applications directory. It proves installer/uninstaller behavior without replacing the user's real `/Applications/Veil.app` or deleting user data.

## Production Readiness Result

Executed:

```bash
./script/production_readiness.sh --checklist-only --json
```

Expected blocking result:

```json
{"status":"blocked","releaseReady":false,"p0Total":37,"passingP0Count":22,"unresolvedP0Count":15,"automatedGate":"not-run"}
```

The automated gate was run separately and passed; it cannot override missing live evidence.

## Remaining Live Evidence

- [ ] `BLOCKED` — measure Windows guest CPU and bytes sent for a static 1440×900 Notepad window before and after duplicate suppression.
- [ ] `BLOCKED` — prove a real Windows Agent emits a changed first frame, then payload-free heartbeats during a long idle period.
- [ ] `BLOCKED` — prove input after idle returns capture to the active cadence and produces a new full frame without visible lag.
- [ ] `BLOCKED` — prove subscribe replacement, unsubscribe, app close, and agent shutdown each force a real first frame on the next subscription.
- [ ] `BLOCKED` — run the real Notepad/Calculator/Paint app loop with pointer, keyboard/IME, clipboard, stable sizing, and 1440×900 display evidence.
- [ ] `BLOCKED` — complete three consecutive clean full-gate passes required for Phase 0 exit.

## Explicitly Deferred

- Separate binary frame WebSocket/channel.
- Changed-region rectangle detection and tile compositing.
- Hardware-accelerated capture/encoding.
- A production claim about CPU, bandwidth, latency, or Parallels equivalence before live measurements exist.
