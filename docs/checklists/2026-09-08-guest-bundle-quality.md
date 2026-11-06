# Guest bundle publication quality

Follow-up to [corrupt-frame and live quality](2026-09-08-corrupt-frame-and-live-quality.md).
The installed guest lacked current binary-frame and acknowledgement capabilities,
so publication and guest deployment were examined before further live compatibility
claims.

## Publisher correction

The Bash publisher previously deleted `app` before running `dotnet publish`.
A compiler error therefore destroyed the previous usable bundle, and an exit-zero
compiler with incomplete outputs could replace it with a broken one. Concurrent
publishers also wrote into the same directory.

The macOS/Linux publisher now builds in a unique sibling directory, checks four
nonempty required outputs, refuses unexpected targets, serializes publishers with
an owned lock, and promotes the complete folder. A successful publish retains
the prior folder at `app.previous`, rotating only the older backup. A failed
promotion restores the prior folder; if restoration also fails, it retains the
old files and reports the recovery path. Generated backup/staging/lock paths are
excluded from Git.

This is failure-safe publication, not a crash-atomic transaction. Consumers must
not stage media during the brief rename gap. Hard kills can leave a lock and
staging directory requiring operator inspection. The Windows PowerShell publisher
and in-guest installer now stage and validate the complete four-file bundle before
promotion, and retain the previous installed bundle at `app.previous`. This
protects the app payload; support-script copies, scheduled-task registration,
firewall rules, and sparse-package registration remain separate failure domains.
PowerShell publisher, installer, and repair app replacement share an atomic
`.veil-agent-bundle.lock`; lock release is protected even when rollback or staging
cleanup encounters a filesystem error. Native `dotnet publish` exit codes are
checked before artifact validation, so a failed compiler cannot be promoted merely
because it left stale-looking files in the staging directory.

## Automated and build evidence

- Seven initial publisher behavior tests failed before implementation and passed
  afterward. They execute the real Bash script against temporary files, with only
  the external compiler and an injected rename failure substituted.
- Independent review requested rollback-failure coverage. That case and first-
  publish coverage were added; all nine publisher cases pass. Bash-specific cases
  are explicitly skipped on Windows, not presented as PowerShell verification.
- Full Windows-agent contract harness: 38 passed, 0 failed, including the
  PowerShell staging/rollback contract. PowerShell syntax still requires a
  Windows validation environment; no PowerShell runtime is installed on this Mac.
- Full .NET 8 agent suite on macOS: 143 passed, 0 failed. This is not Win32 runtime
  or packaged-identity verification.
- Real self-contained `win-arm64` publication succeeded. `file` identifies
  `app/VeilAgent.exe` as an Aarch64 Windows PE executable.
- The retained backup's executable and DLL SHA-256 match their pre-publish values:
  `48e2cbb0fda56276355122203bd40b992aab53feea5b434c5fae5a4d573f9bce`
  and `ffc14ff37c7dcbfd58535916f61e60a264cb5b4b27b796213c58eb76945f37fd`.
- The newly published DLL SHA-256 is
  `fea27c2119465b1fadd68e8967d7c0eb4467d53c33845338d0b43bb2cfb3f444`.

Logs: `/tmp/veil-bundle-publish-red.log`, `/tmp/veil-bundle-publish-green.log`,
`/tmp/veil-bundle-contract-final.log`, `/tmp/veil-bundle-agent-tests.log`, and
`/tmp/veil-bundle-publish-real.log`.

## Local media preparation

The VM was confirmed stopped. Previous support media and the VM profile were
retained privately under `/tmp/veil-agent-rollout.szqFIt8t/`. `veil-vmctl prepare`
used the already configured, existing Windows and driver ISO paths. It preserved
the installed system disk and rebuilt guest tools media; the staged DLL matches
the new build's hash above. No Windows image or generated binary is committed.

## Live deployment and app capture

The existing installed Windows VM was booted normally. Before updating the agent,
the attached `VEIL_AUTO` media was selected by its unique volume label and its
DLL SHA-256 checked against the build above. The previous installed `app` was
copied to `C:\Users\Veil\AppData\Local\Veil\Agent\app.before-szqFIt8t`.
The media's existing installer then installed the new self-contained bundle.
This was an operator-assisted rollout through the guest console, not proof of a
finished one-click update experience. The installed Windows system disk was not
replaced or migrated.

Health after replacement advertised `binaryFrameChannel`, `operationAcks`, and
`windowResize`. The version string remained `0.1.0`; it alone cannot distinguish
the old deployment from this build. Package identity remained unavailable and
shared folders remained unready. Installation warned that logon-task registration
and firewall-rule refresh were denied; successful current-session connectivity
does not prove that either configuration change succeeded.

| App | Live result | Captured frame | Subscribe-to-first-frame observation |
| --- | --- | --- | --- |
| Notepad | Launch and PNG frame received | 600 × 393, 3,316 encoded bytes | 16 ms |
| Calculator | Launch and PNG frame received | 500 × 532, 2,130 encoded bytes | 11 ms |
| Paint | Launch and PNG frame received | 704 × 500, 4,167 encoded bytes | 1,726 ms |

These are single subscription observations, excluding app launch and the fixed
pre-subscription wait. Paint exceeded the 1,000 ms fresh-frame target but stayed
within the 5,000 ms stale timeout. The prior legacy-agent Paint failure did not
recur; this observation does not establish its original root cause.

A separate binary-frame collector overlapping Calculator launch decoded five
key frames, totaling 71,425 wire bytes, with zero no-surface, payload/rectangle,
surface-size, or undecodable-payload drops. No delta tiles were observed. The
collector outlived the short app-proof subscription, so its whole-run FPS is not
a sustained-rendering benchmark. This proves current guest binary delivery and
host decoding, not live corruption injection or input/clipboard behavior.

Live evidence is under `/tmp/veil-agent-rollout.szqFIt8t/`: `prepare.log`,
`doctor.json`, `start.json`, `agent-after.json`, `notepad-proof.json`,
`calculator-proof.json`, `paint-proof.json`, and `binary-frames.json`.

## Restart check

The first QMP normal-powerdown request did not finish within its 30-second wait.
A later status report confirmed `stopped` and VNC refused connections; no force
stop was used. A new ordinary start then reached the Windows loading and sign-in
screens, but took several minutes rather than the first boot's shorter wait.
Five 45-second and two 30-second health waits during boot/sign-in expired. A QMP disk sample recorded
930,207,744 bytes read and 50,190,848 bytes written, with no reported failed reads
or writes. This does not identify the cause of the long boot, which remains a
separate product-readiness issue. The VM profile JSON is identical to the saved
pre-rollout copy.

At `02:02:46Z`, a subsequent health request connected without manually starting
or repairing the guest agent after reboot. Both `binaryFrameChannel` and
`operationAcks` were still true. This confirms automatic startup of the updated
agent in this existing VM; it does not establish that the installer's denied task
registration or firewall updates succeeded, nor fresh-install auto-start.
The first connected check was observed 8 minutes 57 seconds after the launch
record's `01:53:49Z` start time. Polling gaps and diagnostic work mean this is not
an exact time-to-ready measurement. The earlier boot's much shorter wait must
not be generalized into a startup-performance claim.

The installed start script now treats loopback health as the product readiness
gate used by QEMU host forwarding. It skips the slower guest-IPv4 probe by default;
`-RequireGuestAddress` keeps that probe available for the elevated connectivity
repair diagnostic. This separates host reachability from an optional in-guest
network diagnostic and avoids adding several WebSocket retries to every logon.

Restart evidence: `restart-powerdown.json`, `restart-stopped-final.json`,
`restart-start.json`, `restart-agent.json` through `restart-agent-8.json`,
`restart-display-4.json` (sign-in), `restart-disk-activity.json`, and
`restart-run-display.json` (desktop). Opening and dismissing the guest Run dialog
did not invoke an agent start, installer, or repair command.

After automatic reconnection, Notepad again launched and delivered a 600 × 393
PNG (3,283 encoded bytes; 9 ms subscribe-to-first-frame observation). Evidence:
`restart-notepad-proof.json`. No text was entered into document apps, and no
clipboard proof was run.

After the final app check, normal QMP powerdown was requested again. The initial
30-second wait did not confirm exit, but `final-status.json` reported `stopped`
at `02:04:30Z`, and the recorded QEMU PID was no longer present. The VM was left
stopped without force-stop. Host and guest agent backups remain available.

## Review and remaining checks

Independent read-only re-review approved the publisher and nine regression cases
with no remaining findings. The contract harness was rerun after rollout:
37 passed, 0 failed (`/tmp/veil-bundle-contract-completion.log`). Bash syntax and
`git diff --check` also passed. Restart persistence and final normal shutdown
were verified as described above.
Live input/clipboard, AppKit window interaction, signed
package identity, shared-folder readiness, and NVMe suspend/resume remain outside
this verification. No Parallels performance or compatibility parity is claimed.
