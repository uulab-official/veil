import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

import { validateSharedFolder } from "../src/validate-shared-folder.mjs";

function readFixture(name) {
  return JSON.parse(readFileSync(new URL(`../fixtures/${name}`, import.meta.url), "utf8"));
}

const allFixtures = [
  "shared-folder.ready.json",
  "shared-folder.awaiting-host-mount.json",
  "shared-folder.awaiting-guest-share-elevation.json",
  "shared-folder.awaiting-guest-share-firewall.json",
  "shared-folder.awaiting-guest-agent.json",
  "shared-folder.awaiting-vm.json",
  "shared-folder.unsupported-host-smb.json",
  "shared-folder.host-port-unavailable.json",
  "shared-folder.disabled.json"
];

test("validates every shared folder readiness fixture", () => {
  for (const name of allFixtures) {
    const report = readFixture(name);
    assert.equal(validateSharedFolder(report), report, name);
  }
});

test("rejects a forward bound to every interface instead of loopback", () => {
  const report = readFixture("shared-folder.ready.json");
  report.capability.hostForwardClause = "hostfwd=tcp::18445-:445";

  // An empty host address publishes the guest's SMB server on the local network, which is the whole
  // thing the loopback binding exists to prevent.
  assert.throws(() => validateSharedFolder(report), /127\.0\.0\.1/);
});

test("rejects a forward that does not reach the guest SMB port", () => {
  const report = readFixture("shared-folder.ready.json");
  report.capability.hostForwardClause = "hostfwd=tcp:127.0.0.1:18445-:139";

  assert.throws(() => validateSharedFolder(report), /guest SMB port/);
});

test("rejects a mount URL pointing at a network host", () => {
  const report = readFixture("shared-folder.ready.json");
  report.capability.hostMountURL = "smb://192.168.1.44:18445/VeilShared";

  assert.throws(() => validateSharedFolder(report), /loopback forward/);
});

test("rejects a mount URL that does not name the share", () => {
  const report = readFixture("shared-folder.ready.json");
  report.capability.hostMountURL = "smb://127.0.0.1:18445/SomethingElse";

  assert.throws(() => validateSharedFolder(report), /shareName/);
});

test("rejects a supported capability that is not wired into the boot plan", () => {
  const report = readFixture("shared-folder.ready.json");
  report.capability.isWiredIntoBootPlan = false;

  assert.throws(() => validateSharedFolder(report), /wired into the boot plan/);
});

test("rejects an unsupported capability that claims to be wired into the boot plan", () => {
  const report = readFixture("shared-folder.host-port-unavailable.json");
  report.capability.isWiredIntoBootPlan = true;

  assert.throws(() => validateSharedFolder(report), /only a supported/);
});

test("rejects isSupported drifting from the capability state", () => {
  const report = readFixture("shared-folder.disabled.json");
  report.capability.isSupported = true;

  assert.throws(() => validateSharedFolder(report), /must agree with/);
});

test("rejects host-smb reported as anything but unsupported", () => {
  const report = readFixture("shared-folder.unsupported-host-smb.json");
  report.capability.state = "supported";
  report.capability.isSupported = true;

  // Veil does not turn on macOS File Sharing, so this transport can never be reported as working.
  assert.throws(() => validateSharedFolder(report), /host-smb|only the guest-smb/);
});

test("rejects a disabled transport reported as available", () => {
  const report = readFixture("shared-folder.disabled.json");
  report.capability.state = "notConfigured";

  assert.throws(() => validateSharedFolder(report), /none transport/);
});

test("rejects a guest claiming a share inside a folder that does not exist", () => {
  const report = readFixture("shared-folder.ready.json");
  report.guest.directoryExists = false;

  assert.throws(() => validateSharedFolder(report), /directoryExists is false/);
});

test("rejects a guest claiming write access without a share", () => {
  const report = readFixture("shared-folder.awaiting-guest-share-elevation.json");
  report.guest.isWritable = true;

  assert.throws(() => validateSharedFolder(report), /isShared is false/);
});

test("rejects an unsupported guest that still claims a listening server", () => {
  const report = readFixture("shared-folder.awaiting-guest-share-elevation.json");
  report.guest.isSupported = false;

  assert.throws(() => validateSharedFolder(report), /isSupported/);
});

test("rejects a missing share that does not admit needing an administrator", () => {
  const report = readFixture("shared-folder.awaiting-guest-share-elevation.json");
  report.guest.requiresElevation = false;

  assert.throws(() => validateSharedFolder(report), /administrator/);
});

test("rejects an elevation-blocked guest with no command to run", () => {
  const report = readFixture("shared-folder.awaiting-guest-share-elevation.json");
  delete report.guest.shareCommand;

  assert.throws(() => validateSharedFolder(report), /shareCommand/);
});

test("rejects a guest sharing a different name than the host asked for", () => {
  const report = readFixture("shared-folder.ready.json");
  report.guest.shareName = "SomethingElse";

  // The Mac would mount one thing while Windows published another, which is exactly the silent
  // mismatch the host-supplied names exist to prevent.
  assert.throws(() => validateSharedFolder(report), /share name the host asked for/);
});

test("rejects a guest sharing a different folder than the host asked for", () => {
  const report = readFixture("shared-folder.ready.json");
  report.guest.guestDirectoryPath = "C:\\Somewhere";

  assert.throws(() => validateSharedFolder(report), /folder the host asked for/);
});

test("rejects a mount path outside /Volumes", () => {
  const report = readFixture("shared-folder.ready.json");
  report.hostMount.mountPath = "/Users/example/VeilShared";

  assert.throws(() => validateSharedFolder(report), /\/Volumes/);
});

test("rejects a mount path reported while nothing is mounted", () => {
  const report = readFixture("shared-folder.awaiting-host-mount.json");
  report.hostMount.mountPath = "/Volumes/VeilShared";

  assert.throws(() => validateSharedFolder(report), /must be absent/);
});

test("rejects a mounted host with no mount path", () => {
  const report = readFixture("shared-folder.ready.json");
  delete report.hostMount.mountPath;

  assert.throws(() => validateSharedFolder(report), /hostMount\.mountPath/);
});

test("rejects readiness that does not follow from the reported state", () => {
  const report = readFixture("shared-folder.ready.json");
  report.readiness = "awaitingHostMount";

  assert.throws(() => validateSharedFolder(report), /must report readiness 'ready'/);
});

test("rejects an unsupported capability that is not reported as unavailable", () => {
  const report = readFixture("shared-folder.disabled.json");
  report.readiness = "awaitingVM";

  assert.throws(() => validateSharedFolder(report), /readiness 'unavailable'/);
});

test("rejects readiness unavailable on a supported capability", () => {
  const report = readFixture("shared-folder.ready.json");
  report.readiness = "unavailable";

  assert.throws(() => validateSharedFolder(report), /requires an unsupported capability/);
});

test("rejects a guest report while the VM is not running", () => {
  const report = readFixture("shared-folder.awaiting-vm.json");
  report.guest = readFixture("shared-folder.ready.json").guest;

  // A guest cannot have answered while the machine was off, so this is a fabricated report rather
  // than a stale one.
  assert.throws(() => validateSharedFolder(report), /while the VM is not running/);
});

test("reports awaitingVM rather than a guest-agent fault when Windows is off", () => {
  const report = readFixture("shared-folder.awaiting-vm.json");
  report.readiness = "awaitingGuestAgent";

  assert.throws(() => validateSharedFolder(report), /awaitingVM/);
});

test("rejects an awaitingVM report that does not say how to start Windows", () => {
  const report = readFixture("shared-folder.awaiting-vm.json");
  report.nextActions = ["Wait."];

  assert.throws(() => validateSharedFolder(report), /must say how to start Windows/);
});

test("rejects an awaitingGuestAgent report that ignores an agent predating the protocol", () => {
  const report = readFixture("shared-folder.awaiting-guest-agent.json");
  report.nextActions = report.nextActions.filter((action) => !action.includes("qemu-install-agent"));

  assert.throws(() => validateSharedFolder(report), /predates this protocol/);
});

test("rejects an awaitingGuestAgent report with no reconnection command", () => {
  const report = readFixture("shared-folder.awaiting-guest-agent.json");
  report.nextActions = ["Reinstall it with veil-vmctl qemu-install-agent --json."];

  assert.throws(() => validateSharedFolder(report), /must point at the guest-agent wait command/);
});

test("rejects an elevation-blocked report that hides the share command", () => {
  const report = readFixture("shared-folder.awaiting-guest-share-elevation.json");
  report.nextActions = report.nextActions.filter((action) => !action.includes("New-SmbShare"));

  assert.throws(() => validateSharedFolder(report), /elevated share command/);
});

test("rejects an unreachable SMB server report without the firewall command", () => {
  const report = readFixture("shared-folder.awaiting-guest-share-firewall.json");
  report.nextActions = report.nextActions.filter((action) => !action.includes("Enable-NetFirewallRule"));

  assert.throws(() => validateSharedFolder(report), /firewall command/);
});

test("rejects a firewall next action that does not say the guest network is isolated", () => {
  const report = readFixture("shared-folder.awaiting-guest-share-firewall.json");
  report.nextActions = report.nextActions.filter((action) => !action.includes("usermode NAT"));

  // Told to open SMB without that context, a user reasonably assumes they are exposing SMB to their
  // own network.
  assert.throws(() => validateSharedFolder(report), /isolated/);
});

test("rejects an awaitingHostMount report without the mount URL", () => {
  const report = readFixture("shared-folder.awaiting-host-mount.json");
  report.nextActions = ["Mount the share."];

  assert.throws(() => validateSharedFolder(report), /URL that mounts the share/);
});

test("rejects a ready report that does not contrast the old 50 MB copy path", () => {
  const report = readFixture("shared-folder.ready.json");
  report.nextActions = ["The shared folder is live."];

  assert.throws(() => validateSharedFolder(report), /50 MB/);
});

test("rejects an unsupported host-smb report that hides the working alternative", () => {
  const report = readFixture("shared-folder.unsupported-host-smb.json");
  report.nextActions = report.nextActions.filter((action) => !action.includes("guest-smb"));

  assert.throws(() => validateSharedFolder(report), /guest-smb/);
});

test("rejects an unsupported host-smb report that hides the File Sharing tradeoff", () => {
  const report = readFixture("shared-folder.unsupported-host-smb.json");
  report.nextActions = report.nextActions.filter((action) => !action.includes("every network interface"));

  assert.throws(() => validateSharedFolder(report), /guest-only/);
});

test("rejects a port-conflict report that does not name the port", () => {
  const report = readFixture("shared-folder.host-port-unavailable.json");
  report.nextActions = ["Free the port and restart the VM."];

  assert.throws(() => validateSharedFolder(report), /name the port/);
});

test("rejects confusing the macOS staging folder with the mounted share", () => {
  const report = readFixture("shared-folder.ready.json");
  report.hostStagingFolderPath = report.hostMount.mountPath;

  // VMProfile.sharedFolderPath is named like the feature but holds VeilAutoInstall.iso and is not
  // shared with Windows. Conflating them tells a user their Mac folder is visible in the guest.
  assert.throws(() => validateSharedFolder(report), /install-media folder/);
});

test("rejects the staging folder standing in for the guest share folder", () => {
  const report = readFixture("shared-folder.ready.json");
  report.hostStagingFolderPath = report.capability.expectedGuestDirectoryPath;

  assert.throws(() => validateSharedFolder(report), /guest share folder/);
});

test("rejects an unrecognized override environment variable", () => {
  const report = readFixture("shared-folder.ready.json");
  report.capability.overrideEnvironmentVariable = "VEIL_SHARE";

  assert.throws(() => validateSharedFolder(report), /documented override/);
});

test("rejects an empty nextActions list", () => {
  const report = readFixture("shared-folder.ready.json");
  report.nextActions = [];

  assert.throws(() => validateSharedFolder(report), /non-empty array/);
});

test("rejects a report of the wrong kind", () => {
  const report = readFixture("shared-folder.ready.json");
  report.kind = "vmSnapshotAction";

  assert.throws(() => validateSharedFolder(report), /Unsupported shared folder kind/);
});
