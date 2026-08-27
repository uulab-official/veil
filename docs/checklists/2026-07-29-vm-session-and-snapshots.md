# VM Session Persistence and Snapshots

Date: 2026-07-29

Closes the roadmap gap where `VMRuntimeState.suspended` was representable but
unreachable, and adds the first v2.0 snapshot-management slice. Also fixes two
protocol-boundary defects found while auditing the notification bridge.

## Protocol Contract Gap

- [x] `notification.received` was documented in `docs/protocol.md`, implemented in
      the Swift host and the .NET agent, and asserted by the app-runtime-status
      harness, but it was missing from `MessageType` in
      `packages/protocol/src/messages.mjs`. `parseMessage()` therefore rejected a
      real guest notification as `unknown_message_type`, which would have broken
      `harness/fake-agent` and `harness/fake-host` the moment either simulated one.
- [x] Added `validateNotificationReceived()` with the same rules the notification
      proof harness already enforced: required `notificationId`/`title`/ISO
      `receivedAt`, optional `appId`/`appName`/`body`/`sourceAumid` because Windows
      notifications can come from apps Veil never launched.
- [x] Added the missing `harness/protocol-fixtures/notification.received.json`
      fixture and refreshed the stale fixture index in that directory's README.
- [x] Fixed `URLSessionWebSocketTransport.isUnsolicitedEvent`: it skipped
      `window.frame`, `window.updated`, `window.closed`, and `clipboard.text.set`
      while awaiting a request reply, but not `notification.received`. A toast
      arriving mid-request would have been consumed as that request's reply and
      decoded as the wrong type.

## Session Suspend and Resume

- [x] Added `QEMUQMPClient`, the first QMP client that reads replies. The existing
      key and pointer senders write to QMP through `nc` and discard the answer,
      which is fine for fire-and-forget input but cannot support pause, resume, or
      snapshots where the reply *is* the result. Same transport, no new dependency,
      with `id` correlation per command.
- [x] Suspend uses QEMU's migration path (`stop` -> `migrate exec:cat > file` ->
      poll `query-migrate` -> `quit`) rather than `savevm`. `savevm` needs qcow2;
      Veil ships `if=none,id=system,format=raw`. Streaming RAM and device state to a
      sidecar file works on the disk format Veil actually ships.
- [x] The memory-state file lives next to the virtual disk as
      `Windows 11 Arm.vmsave`, not under `Diagnostics`. Diagnostics bundles are
      metadata-only by contract and this file is guest RAM. `.vmsave` is already
      covered by `.gitignore`.
- [x] Resume relaunches QEMU with `-incoming exec:cat '<file>'` and then sends
      `cont`. The launch path is shared with `start()` so argument building and
      launch-record writing stay in one place; the only behavioral differences are
      the `-incoming` argument and suppressing the installer boot-key helper so a
      resumed Windows session receives no spurious keystrokes.
- [x] Resume compares a recorded machine fingerprint (FNV-1a over the
      machine-shaping arguments, excluding per-launch plumbing) against the
      rebuilt plan and refuses a mismatch. A migration stream can only be loaded by
      an identically configured machine.
- [x] The stream is treated as single-use. It is deleted only after the guest is
      confirmed running, preserved when resume fails so the user can retry, and
      **discarded on cold boot** -- otherwise a later resume would replay old RAM
      against a disk that has moved on and corrupt Windows.
- [x] `loadSnapshot()` resolves `.suspended` only when nothing is actually
      executing, so a stale suspension record cannot hide a live Windows session.
- [x] `VMRuntimeBooting` and `VMRuntimeService` gained `suspend`/`resume` as
      requirements with defaults that throw `suspendNotSupported`. Providers that
      cannot persist a session say so instead of silently falling back to stop and
      start, which would lose the user's open apps.
- [x] Added `veil-vmctl vm-suspend`, `vm-resume`, and `vm-session-status`, plus
      `VMRuntimeModel.canSuspend`/`canResume`/`suspend()`/`resume()`. A failed
      resume reports the VM as still suspended, not failed, because the saved state
      is still there to retry.
- [x] Added `harness/vm-session`, which rejects a suspend without durable
      evidence, a resume that still advertises the consumed session, a report that
      claims to be both suspendable and resumable, and any state file under
      `Diagnostics`.

## Snapshots

- [x] Added `veil-vmctl vm-snapshot-list|vm-snapshot-create|vm-snapshot-restore|vm-snapshot-delete`
      over QEMU internal snapshots via QMP `human-monitor-command`.
- [x] Capability detection reads the real disk format from the system drive
      argument, handling both the plan form (`format=raw`) and the lock-safe launch
      form (`driver=raw,...`). A raw disk reports `unsupportedDiskFormat` with the
      `qemu-img convert -p -O qcow2` command, the converted disk path, and the
      reminder to keep the original file until Windows boots from the new one.
- [x] Snapshot capability is reported separately from session persistence, because
      they have different prerequisites. Conflating them would let the UI offer a
      snapshot action that can never succeed on the shipping disk.
- [x] `human-monitor-command` reports failures inside the returned *text*, not as a
      QMP error, so a successful round trip carrying `Error: ...` is treated as a
      failure. Otherwise a refused snapshot would look like a completed one.
- [x] Snapshot names are restricted to `[A-Za-z0-9._-]{1,64}`. They are
      interpolated into a monitor command line, so a name containing a space,
      newline, quote, or semicolon must be refused rather than escaped.
- [x] Create, restore, and delete require a running machine so guest memory and
      disk state stay consistent. Listing falls back to `qemu-img snapshot -l` so a
      user can inspect what they have without booting Windows; `qemu-img` is
      resolved next to the already-discovered `qemu-system-aarch64`.
- [x] Added `harness/vm-snapshots`, which rejects an unsupported report that hides
      the conversion path or the suspend alternative, a succeeded create that does
      not list the new tag, a succeeded delete that still lists it, a mutating action
      that succeeded without a running VM, and a restore that skips guest-agent
      reconnection.

## Verification Status

Unit and harness coverage was written alongside the implementation:

- `apps/mac-host/Tests/VeilHostCoreTests/VMSessionAndSnapshotTests.swift`
  covers QMP command building and reply correlation, shell quoting of the `exec:`
  URI, the fingerprint's stability and collision resistance, the suspend state
  machine including failure and timeout, `-incoming` argument construction, the
  session and snapshot report contracts, and snapshot table parsing and tag policy.
- `harness/vm-session` and `harness/vm-snapshots` carry fixtures plus rejection
  tests for every invariant above.
- `packages/protocol` gained fixture-parse and validation tests for
  `notification.received`.

**These were not executed.** Shell command execution was unavailable in the
session that produced this change (every invocation returned exit 1 with no
output), so `swift build`, `swift test`, and `node --test` have not been run
against this code. Treat the suite as written-but-unverified until someone runs:

```bash
cd apps/mac-host && swift build && swift test
cd packages/protocol && npm test
cd harness/vm-session && npm test
cd harness/vm-snapshots && npm test
```

## Remaining Live Verification

- [ ] Suspend and resume a real Windows 11 Arm guest and confirm the same app
      windows are still open afterwards. **Known risk:** the QEMU migration stream
      includes TPM device state, and Veil restarts the external `swtpm` process on
      every launch. Restoring a stream against a freshly started swtpm may be
      rejected. If it is, the fix is to keep swtpm alive across suspend/resume
      rather than restarting it in the shared launch path.
- [ ] Confirm the resumed session's guest agent reconnects, and decide whether
      resume should run the existing reconnect-restore path automatically.
- [ ] Wire suspend to an automatic idle policy in the app shell to finish the v1.0
      "Automatic VM start and suspend" item; the primitive exists but nothing calls
      it automatically yet.
- [ ] Convert a Windows 11 Arm disk to qcow2 and run the full snapshot
      create/list/restore/delete loop against it. Everything before that point is
      contract-level only.
- [ ] Decide whether Veil should offer disk conversion as a first-class action or
      keep it as a documented manual `qemu-img` step.
