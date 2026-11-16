# Corrupt-frame recovery and live runtime verification

Continuation of [frame recovery quality](2026-09-08-frame-recovery-quality.md).
This pass improves failure recovery and exercises the installed Windows guest.
It is not a Parallels performance or compatibility claim.

## Host correction

A rejected PNG previously left its old compositor surface available. The next
valid delta could then be applied to incomplete pixels and clear the recovery
reason. Even without that delta, unchanged heartbeats kept the damaged screen's
liveness fresh, preventing ordinary stale-stream recovery.

The affected surface is now discarded on image rejection. Deltas require a new
full key frame, and heartbeats cannot refresh a session awaiting that key frame.
Other HWND surfaces remain independent. The protocol's wire shapes are unchanged;
its binary-frame handling rules document the correction.

Two new parameterized tests cover six cases: corrupt and dimension-mismatched
payloads on key frames and deltas, independent windows, subsequent delta rejection,
heartbeat rejection, stale assessment, and restoration by a valid key frame.
Before implementation, the focused run failed with 24 assertion issues in those
tests (19 tests across two suites ran).

Independent review identified a mixed-transport regression in the first correction:
a good JSON full frame could update the display without clearing binary recovery
state. Three more parameter cases reproduced that problem and invalid JSON recovery
with seven assertion issues. Recovery now validates a JSON full image through the
compositor, restores its base, and counts the frame exactly once. Invalid payloads
cannot advance its timing. Normal JSON delivery outside recovery is unchanged.

## Live Windows evidence

The configured installed Windows 11 Arm VM was stopped before this pass.
`qemu-doctor --json` reported ready. It was booted with `qemu-start --json
--wait-seconds 5`, without reinstalling Windows or changing the storage device.

The initial 45-second agent wait expired during boot. A subsequent 30-second
wait connected after 10 seconds. The installed agent reported version `0.1.0`,
an interactive session, and JSON window capture. It did **not** advertise the
current source's binary frame channel or operation acknowledgements. This is
legacy-agent compatibility evidence, not execution of the latest guest changes.

| App | Live result | Captured frame | Subscribe-to-first-frame observation |
| --- | --- | --- | --- |
| Notepad | Launch and PNG frame received | 600 × 393, 3,316 encoded bytes | 18 ms |
| Calculator | Launch and PNG frame received | 500 × 500, 2,010 encoded bytes | 38 ms |
| Paint | Failed: `app_launch_failed`, no top-level window discovered | None | Not measured |

The two timing observations come from `app-window-proof`; they exclude the launch
and its fixed pre-subscription wait, and are single observations, not end-to-end
latency benchmarks. Read-only VNC screenshots also showed the Notepad and
Calculator interfaces. No keyboard text, clipboard changes, or user-document
edits were used. Paint's failure remains unresolved on the installed guest;
retest after deploying the current guest build before assigning a current-source
root cause.

The VM received QMP `system_powerdown`. Its initial 30-second report did not yet
confirm exit, but a subsequent `vm-session-status --json` reported `stopped` and
the VNC endpoint refused connections. No force-stop or disk migration was used.

Local evidence (temporary files, not portable release artifacts):

- `/tmp/veil-live-quality-doctor.json`
- `/tmp/veil-live-quality-start.json`
- `/tmp/veil-live-quality-agent-wait.json`
- `/tmp/veil-live-quality-agent-wait-2.json`
- `/tmp/veil-live-quality-notepad-proof.json`
- `/tmp/veil-live-quality-calculator-proof.json`
- `/tmp/veil-live-quality-paint.err`
- `/tmp/veil-live-quality-notepad-display.json`
- `/tmp/veil-live-quality-paint-display.json`
- `/tmp/veil-live-quality-powerdown.json`
- `/tmp/veil-live-quality-final-status.json`

## Remaining boundaries

Latest-guest binary delivery and operation acknowledgements, live input/clipboard,
Paint compatibility, and full AppKit window interaction remain unproved by this
live check. The configured NVMe VM still reports suspend/resume unsupported.
Strict cross-connection frame-generation fencing and unknown lost transport tiles
remain separate work; this fix concerns decoded tiles whose images are rejected.

## Final local verification

| Check | Result |
| --- | --- |
| Focused compositor, recovery-ordering, and mixed-delivery tests | 20 tests in 3 suites passed |
| `swift test --package-path apps/mac-host` | 830 tests in 78 suites passed |
| Real URLSession transport against the fake guest | 9 tests passed |
| `./script/build_and_run.sh --verify` | Build, ad-hoc signing, bundle validation, and AppKit launcher contract passed |
| Independent read-only re-review | Approved; no remaining scoped Critical, Important, or Minor findings |
| `git diff --check` | Passed |

Final test logs are `/tmp/veil-mixed-frame-green.log`,
`/tmp/veil-mixed-frame-swift-all.log`, `/tmp/veil-mixed-frame-socket.log`, and
`/tmp/veil-mixed-frame-app-build.log`. The new local bundle is `dist/Veil.app`,
not a notarized release. Its launch report records one visible main window and
zero duplicates; `isAppActive` and `isMainWindowKey` were false, so this does not
prove foreground activation or input focus. The test process was stopped after
verification, and the VM was again confirmed stopped.

The .NET guest and complete Node harness suites were not rerun in this host-only
code pass. Earlier uncommitted changes were preserved; nothing was committed or
pushed.
