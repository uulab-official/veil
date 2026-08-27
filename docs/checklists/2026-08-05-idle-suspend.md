# Automatic Idle Suspend

Date: 2026-08-05

Finishes the second half of a **v1.0** roadmap item. The roadmap already said it
plainly: "The suspend/resume primitive now exists (`veil-vmctl vm-suspend`,
`vm-resume`, `vm-session-status`, and `VMRuntimeModel.suspend()`/`resume()`);
wiring it to an automatic idle policy in the app shell is the remaining half."

## The Gap, Stated Precisely

When every mirrored Windows app window closes, Veil waits 8 seconds and then
**stops** the VM. Stopping means Windows shuts down and every open app, unsaved
document, and browser tab is gone. Reopening an app then pays a full cold boot.

That is not what the code claims. `quietRuntimeStatus()` already returns
`recommendedAction = "stop-or-suspend-runtime"` — the name promises suspend — and
`VMProfile.suspendOnQuit` exists and defaults to `true`. Neither is honoured.
`suspendOnQuit` is read by nothing at all; the whole idle path calls
`vmModel.stop()` in three places.

So the machinery to suspend has existed since 2026-07-29 and the idle policy has
never used it. This closes that.

## Track A: Make the Status Say Which One Will Happen

- [x] `WindowsAppRuntimeQuietPolicyStatus` gains `quietMode`, `canSuspendSession`,
      and `recommendedSuspendCommand`. A single boolean could not express the
      difference between "will suspend, apps survive" and "will stop, apps are
      lost", and that difference is the whole point.
- [x] `recommendedAction` stops saying `stop-or-suspend-runtime`. It now names the
      action that will actually run: `suspend-runtime` or `stop-runtime`. An
      ambiguous recommendation is worse than either answer, because a reader
      cannot tell whether their apps are about to be closed.
- [x] `canSuspendSession` is derived from the same
      `VMSessionActionReportFactory.persistenceSummary` the CLI uses, so the app
      and `vm-session-status` can never disagree about whether suspend works.
- [x] `recommendedStopCommand` stays present whenever the runtime can be quieted.
      Stop remains the fallback, and the existing harness contract requires it.

## Track B: Use It

- [x] The automatic idle task suspends when the session can be persisted and stops
      otherwise, rather than always stopping.
- [x] The manual **Quiet Windows** action follows the same resolved mode, so the
      menu item and the automatic path can never do different things.
- [x] Suspend failure falls back to stop rather than leaving a half-quiet VM. A
      failed memory-state save leaves the guest paused, which is the one state the
      user cannot act on from the launcher.
- [x] Reopening a Windows app resumes a suspended session instead of cold booting,
      so the round trip is actually lossless.

## Track C: Automation Surface

- [x] New `suspend-runtime` app-runtime action, with its own `runtimeSuspend`
      report field.

Deliberately **not** overloaded onto `stop-runtime`. That action's contract pins
`runtimeStop.state === "stopped"`, and quietly making it suspend instead would
either break the harness or force the harness to stop checking the thing it
exists to check. Two actions, two honest contracts.

## Non-Goals, Stated Rather Than Skipped

- **`VMProfile.suspendOnQuit` is still not read.** Making the idle mode a user
  preference needs the flag on `VMRuntimeSnapshot` so the status report can see
  it, which changes a Codable type that several diagnostics fixtures pin. This
  slice resolves the mode from *capability* only. The flag stays dead, and it is
  named here so the next slice does not have to rediscover it.
- **The 8 second delay is unchanged.** It was not measured before and is not
  measured now; changing it would be a second guess on top of the first.
- **Idle is still "no mirrored app windows".** Real idle detection (no input, no
  frame changes) is a different feature.

## Design Notes Worth Keeping

- Suspend is attempted only when `canSuspendSession` **and** the VM is actually
  running. A `.suspended` VM is already quiet and a `.starting` one has no
  consistent guest state to stream.
- The fallback direction is one-way on purpose: suspend, and if that fails, stop.
  Never the reverse. Stopping is always possible, so a stop failure has no safe
  second attempt.
- The resolved mode is computed once and reported, then acted on. The alternative
  — deciding at the moment of action — would let the UI advertise one outcome and
  perform the other.

## Verification Status

**Not executed.** Shell command execution has been unavailable for this entire
session and it is not a permissions problem: `echo` returns exit 1 with no
output.

```bash
cd apps/mac-host && swift build && swift test
cd harness/app-runtime-status && npm test
cd harness/app-runtime-action && npm test
```

## Remaining Live Verification

- [ ] Open Notepad with unsaved text, close the mirrored window, wait past the
      idle delay, then reopen Notepad. The unsaved text must still be there. That
      single check is the whole feature.
- [ ] Confirm the suspend path is taken by checking `vm-session-status --json`
      reports `suspended` rather than `stopped` after the idle delay.
- [ ] Force a suspend failure (for example by making the state file path
      unwritable) and confirm Veil falls back to stopping rather than leaving the
      guest paused and unreachable.
- [ ] Confirm the TPM hazard from the 2026-07-29 slice does not bite here: the
      migration stream carries TPM device state while Veil restarts `swtpm` on
      every launch. If resume fails on TPM state, keeping swtpm alive across
      suspend/resume is the fix, and idle suspend must fall back to stop until
      then.
- [ ] Measure how long a resume takes against a cold boot. If resume is not
      clearly faster, this feature is not worth its risk and should be reverted
      to stopping.
