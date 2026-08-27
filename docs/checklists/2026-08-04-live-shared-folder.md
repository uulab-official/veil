# Live Shared Folder

Date: 2026-08-04

Closes the last unstarted **v1.0** roadmap item. Every previous slice in this
push worked on graphics; this is the first non-graphics Parallels gap.

## What Existed Before

Nothing that deserved the name. `docs/protocol.md` said it plainly:

> there is no live/writable host-guest filesystem share

What existed was `file.open.request`: a one-shot, base64-encoded, 50 MB-capped
copy of a single file over the control WebSocket, written into an
agent-controlled drop directory and opened with an app. Useful for drag-and-drop.
Not a shared folder — no live view, no writes flowing back, no directory, and a
size cap that a phone photo can exceed.

`VMProfile.sharedFolderPath` already existed and is *named* like the feature, but
it is a host staging directory whose only real job is holding
`VeilAutoInstall.iso`. It was never shared with the guest. This slice keeps that
meaning intact rather than repurposing the field, because the boot plan derives
the unattended-install ISO path from it.

## Transport Selection

This was the whole decision, and most of the obvious answers are wrong on this
host. Ruled out by research, not by preference:

- **virtio-9p / virtfs.** No Windows guest driver exists. The 9p client inside
  WSL is not a mountable filesystem driver for regular Windows. Confirmed by
  [UTM issue #4389](https://github.com/utmapp/UTM/issues/4389).
- **virtio-fs.** The guest half is fine — the virtio-win project ships a
  WinFsp-based user-mode filesystem. The host half is the problem: `virtiofsd`
  has no macOS port for QEMU. UTM offers VirtioFS on macOS only through Apple's
  Virtualization.framework, which does not run Windows guests.
- **QEMU's built-in usermode SMB (`-netdev user,smb=...`).** QEMU shells out to
  `/usr/sbin/smbd`, which on macOS is Apple's SIP-protected binary rather than
  Samba's, and Homebrew installs Samba's as `samba-dot-org-smbd`. On top of
  that, Samba 4.17+ refuses to run as a non-root user, which is exactly how QEMU
  invokes it. See [Homebrew discussion #3868](https://github.com/Homebrew/discussions/discussions/3868)
  and these [macOS QEMU sharing notes](https://gist.github.com/startergo/dedbfa9090bef0ea5aaf2582a35fe32a).
  Requires the user to install Samba, rebuild QEMU against it, and then work
  around the non-root write failure.

Content from those sources was rephrased for compliance with licensing restrictions.

That leaves exactly one transport with **zero host prerequisites, where Veil
controls both ends**: the guest hosts the share, macOS mounts it.

- Windows ships an SMB *server* (`LanmanServer`) enabled by default.
- macOS ships an SMB *client* (`mount_smbfs`, Finder `smb://`).
- QEMU usermode networking already forwards a host port to the guest — that is
  how the guest agent is reached on 18444.

So the share direction is inverted from the naive expectation. The shared folder
physically lives in the guest and appears on the Mac, not the reverse. That is a
deliberate choice and it is worth being explicit about, because "my Mac home
folder appears inside Windows" is the other half of what Parallels does and this
slice does **not** ship it. That direction needs the host to run an SMB server,
so it is reported as a separate, currently-unavailable transport (`host-smb`)
rather than quietly conflated with the one that works.

## Track A: Host Wiring

- [x] Add `QEMUWindowsSharedFolderTransport` with `guest-smb` (default),
      `host-smb`, and `none`, following the same typed-enum + `Selection` +
      `VEIL_QEMU_*` override shape already used for the network and audio
      devices.
- [x] Forward a host loopback port to the guest's SMB port by appending a
      `hostfwd=` clause to the existing `-netdev user,id=net0` rather than
      adding a second netdev, so the guest keeps one NIC.
- [x] Bind the forward to `127.0.0.1` explicitly.
- [x] **Security fix found along the way:** the pre-existing guest-agent forward
      was `hostfwd=tcp::18444-:18444`. An empty host address binds every
      interface, so the agent control channel — which can launch apps, synthesize
      input, and read/write the clipboard — was reachable from the local network
      with no authentication. Scoped to `127.0.0.1`. The host has always
      connected via `ws://127.0.0.1:18444`, so nothing legitimate depended on the
      wider binding.
- [x] Report the share through the typed runtime configuration instead of a
      one-line path, so a status surface can say what the transport is, where the
      folder is in the guest, and what URL mounts it.
- [x] Add a `shared-folder` readiness check to `qemu-doctor`.

## Track B: Fingerprint Correctness

Adding a `hostfwd` clause changes the `-netdev` argument, and the suspend/resume
machine fingerprint hashes machine-shaping arguments. Left alone, **turning the
shared folder on or off would invalidate a suspended Windows session** and force
a cold boot with no warning.

- [x] Exclude `hostfwd=` and `guestfwd=` clauses from the fingerprint, stripping
      them from inside `-netdev` values while keeping every other component.

This is safe, and it is not the same reasoning as the earlier decision to keep
`-device`/`-netdev` in the fingerprint. Host port forwarding is slirp-side
plumbing: the guest sees an identical NIC with an identical MAC and guest IP
either way, and QEMU migration does not serialize forwarding rules. Including
them buys no protection and causes false rejections. Device topology is
different and stays hashed.

## Track C: Guest Confirmation

A host-side plan proves nothing about whether Windows is actually sharing
anything. The host needs the guest to say so.

- [x] Add `shared.folder.request` / `shared.folder.response` and a `sharedFolder`
      status block on the health response, mirroring the reviewed
      `notificationListener` shape.
- [x] Add the `sharedFolder` capability flag as **optional**, so an agent that
      predates this slice decodes as absent and the host reports
      `agentTooOld` instead of a false negative.
- [x] Guest probe reports the directory, whether the SMB share exists, whether it
      is writable, whether the server is listening, and whether elevation is
      required — with the exact command when it is.
- [x] Never put credentials on the wire. The response carries a
      `requiresCredentials` flag and a recommended action, never a password.

## Non-Goals, Stated Rather Than Skipped

- **Mounting from the CLI.** `shared-folder-status` reports; it does not mount.
  A side-effecting `shared-folder-mount` belongs in a separate command after the
  status path is live-verified.
- **The Mac-folder-into-Windows direction.** Modelled as `host-smb` and reported
  as unavailable with its prerequisite. Enabling macOS File Sharing exposes the
  share on every interface, not just to the guest, which is a real security
  tradeoff a user must opt into knowingly.
- **Credential storage.** The guest needs an account with a password before SMB
  will accept a network logon; Windows rejects blank-password network logons by
  default. Reported as a prerequisite.
- **Replacing `file.open.request`.** Drag-and-drop-to-open is a different
  interaction and still works.

## Contracts the Security Fix Moved

Scoping the agent forward to loopback changed a string that several contracts
pinned literally. Rather than update the literal everywhere, the plan validator
now checks the property that actually matters:

- [x] `harness/qemu-boot-plan` no longer compares the `-netdev` value to one exact
      string. It parses the forwards and enforces that **every** one binds
      `127.0.0.1`, that the guest-agent forward is present, that there is only one
      `-netdev` however many ports are mapped, and that a declared shared-folder
      forward and the arguments agree. The old assertion would have passed a plan
      that bound every interface as long as the string matched.
- [x] `harness/export-diagnostics` now requires `deviceSummary.sharedFolderDevice`,
      for the same reason it already required `audioDevice`: the profile field named
      `sharedFolderPath` is the install-media staging directory, so without this a
      bundle could read as having sharing configured while the guest saw nothing.
- [x] `harness/vm-session` accepts both fingerprint schemes. A report describing an
      older suspend is still a valid report; resume is where the two are told apart.

## Verification Status

Written alongside the implementation:

- `apps/mac-host/Tests/VeilHostCoreTests/SharedFolderTests.swift`: transport selection and
  fallback, loopback-only forward, mount URL/path/share-name consistency, every capability state
  including the deliberate refusal to blame a port conflict that was never observed, host mount
  probing, readiness derivation for all six states, and the next-action content each state owes.
- `apps/mac-host/Tests/VeilHostCoreTests/QEMUWindowsBootPlanTests.swift`: one netdev carrying both
  forwards, no forward for the transports that do not need one, the share dropped rather than the VM
  when the port is taken, and no forward bound to every interface under any combination.
- `apps/mac-host/Tests/VeilHostCoreTests/VMSessionAndSnapshotTests.swift`: fingerprint stability
  across share toggling and forward-address changes, while device topology still changes it.
- `apps/windows-agent/tests/VeilAgent.Tests/SharedFolderProbeTests.cs`: unsafe share names and paths
  refused before any filesystem action, the write probe never run through a share that does not
  exist, and elevation reported with the exact command.
- `apps/windows-agent/tests/VeilAgent.Tests/AgentSessionHealthTests.cs`: health advertises and reports
  the share without preparing it as a side effect.
- `harness/shared-folder`, `harness/qemu-boot-plan`, `harness/export-diagnostics`,
  `packages/protocol`.

**These were not executed.** Shell command execution was unavailable in the
session that produced this change, and it is not a permissions problem: `echo`
itself returns exit 1 with no output, and background processes report as running
without ever executing.

```bash
cd apps/mac-host && swift build && swift test
cd apps/windows-agent && dotnet test
cd packages/protocol && npm test
cd harness/shared-folder && npm test
cd harness/qemu-boot-plan && npm test
cd harness/export-diagnostics && npm test
cd harness/vm-session && npm test
cd harness/mvp-proof && npm test
```

## Remaining Live Verification

- [ ] Boot a real Windows 11 Arm guest and confirm the plan's `hostfwd` clause
      appears in the running QEMU command line.
- [ ] Create the share in the guest with the elevated command the probe reports,
      then confirm `shared-folder-status` flips to ready.
- [ ] Mount from macOS (`open smb://127.0.0.1:18445/VeilShared`) and confirm a
      file written in Finder is visible to a Windows app immediately, and a file
      written by a Windows app appears in Finder without remounting.
- [ ] Confirm a file larger than the old 50 MB `file.open.request` cap copies in
      both directions.
- [ ] Suspend and resume with the share enabled, then toggle the transport and
      resume again, confirming the fingerprint change does **not** invalidate the
      suspended session.
- [ ] Confirm the loopback-scoped agent forward is no longer reachable from
      another machine on the LAN, and that Veil.app still connects.
- [ ] Measure throughput. SMB over slirp usermode networking is the slow path;
      if it is unusable, the next step is a `guestfwd` to a loopback SMB server or
      an NSFileProviderExtension, not more tuning here.
