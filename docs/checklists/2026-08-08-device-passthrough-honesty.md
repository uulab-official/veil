# Device Passthrough: What Veil Cannot Do, and Why

Date: 2026-08-08

**This slice ships no new capability.** It ships an honest answer to two questions
users will ask about a Parallels-class product, and it names the architectural
decision that blocks both — so the next person does not rediscover it.

## The Two Gaps

`docs/roadmap.md` lists USB passthrough and bridged networking as remaining work.
Investigating them turned up the same blocker behind both.

### USB passthrough

QEMU upstream has an open issue titled
[USB passthrough on Apple Silicon is unusable](https://gitlab.com/qemu-project/qemu/-/work_items/2178),
and a separate one stating that
[macOS requires root to pass through USB devices properly](https://gitlab.com/qemu-project/qemu/-/work_items/1951).
UTM — the reference QEMU-on-macOS implementation — carries repeated reports of
`LIBUSB_ERROR_ACCESS` and "Cannot Open USB Device"
([utm#5224](https://github.com/utmapp/UTM/issues/5224),
[utm#3375](https://github.com/utmapp/UTM/issues/3375)). Some Homebrew QEMU builds
have no `usb-host` device at all, because libusb was not linked in.

The cause is not a QEMU bug to wait out. macOS binds most USB devices to a kernel
driver, and libusb cannot take exclusive access away from it without root.

### Bridged and host-only networking

macOS exposes these through the `vmnet` framework (`-netdev vmnet-bridged`,
`vmnet-host`, `vmnet-shared`). Every one of them requires root, or the
`com.apple.vm.networking` entitlement, which Apple grants case by case.

Content from the linked sources was rephrased for compliance with licensing
restrictions.

## The Shared Cause, Named

Both gaps reduce to the same thing, and it is worth stating plainly because it
changes what "Parallels-grade" costs:

**Parallels ships a signed system extension and a privileged helper. Veil runs
QEMU as the logged-in user.**

That is not an oversight, and it is why Veil needs no admin password to install or
run. Closing these two gaps means adopting one of:

1. A privileged helper installed with `SMAppService`/`SMJobBless`, which QEMU is
   launched through for USB and vmnet. Costs an admin prompt at install and makes
   Veil responsible for a root-privileged process.
2. Apple-granted entitlements, which require a distribution relationship Veil does
   not have as an open-source project.
3. Running QEMU under `sudo`, which is unacceptable for a consumer app: it would
   put a user-controlled command line and a network-reachable guest behind root.

Option 3 is refused outright. Options 1 and 2 are real product decisions with
security consequences, not implementation details, so this slice deliberately does
**not** pick one. It makes the choice visible instead.

## Track A: Report It Honestly

Following the pattern already used for snapshots on a raw disk and the `host-smb`
shared folder direction: report `unavailable` with the real reason and the
prerequisite, rather than offering an action that cannot succeed.

- [x] Typed capability for USB passthrough and for each network mode, each stating
      whether it needs a privileged helper and what it would take.
- [x] Detect what the **local** QEMU actually supports rather than assuming. A build
      without libusb has no `usb-host` device at all, which is a different problem
      from a build that has it and cannot get access, and the two need different
      answers.
- [x] Keep the probe off status-polling paths. It shells out to QEMU, so it runs
      only when the diagnostic command asks for it.
- [x] `veil-vmctl device-passthrough-status [--json]`, plus a harness validator that
      refuses a report claiming a capability without naming its prerequisite.

## Non-Goals, Stated Rather Than Skipped

- **No `usb-host` device is added to the boot plan.** Adding a device that fails
  with `LIBUSB_ERROR_ACCESS` at runtime would turn a clear "not supported" into a
  confusing startup failure, and on some builds would stop QEMU from starting at
  all.
- **No `vmnet` netdev is added.** Same reasoning: QEMU exits when it cannot open
  the vmnet interface, so offering it would trade a working NAT setup for a VM
  that does not boot.
- **USB mass storage is not offered as a workaround.** Backing a `usb-storage`
  drive with `/dev/diskN` avoids libusb, but that device node is `root:operator`
  on macOS, so it needs the same privileges. The live shared folder from
  2026-08-04 is the honest answer for moving files, and it needs no privileges.

## Verification Status

**Not executed.** Shell command execution has been unavailable for this entire
session; `swift --version` returns exit 1 with no output.

```bash
cd apps/mac-host && swift build && swift test
cd harness/device-passthrough && npm test
```

## Remaining Live Verification

- [ ] Run `veil-vmctl device-passthrough-status --json` against a real Homebrew
      QEMU and confirm the reported `usb-host` availability matches what
      `qemu-system-aarch64 -device help` actually lists.
- [ ] Repeat against a QEMU built with libusb, and confirm the report changes from
      "device not built in" to "needs a privileged helper".
- [ ] Confirm the report does not slow down `app-runtime-status`, which must not be
      shelling out to QEMU.

## The Decision This Slice Is Waiting On

- [ ] Decide whether Veil adopts a privileged helper. Until then, USB passthrough
      and bridged networking stay honestly unavailable, and that is the gap between
      Veil and Parallels that cannot be closed by writing more host code.
