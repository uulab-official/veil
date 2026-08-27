import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

import { validateDevicePassthrough } from "../src/validate-device-passthrough.mjs";

function readFixture(name) {
  return JSON.parse(readFileSync(new URL(`../fixtures/${name}`, import.meta.url), "utf8"));
}

const allFixtures = [
  "device-passthrough.requires-privileged-helper.json",
  "device-passthrough.usb-host-not-built-in.json",
  "device-passthrough.qemu-unprobed.json"
];

function capability(report, id) {
  return report.capabilities.find((entry) => entry.id === id);
}

test("validates every device passthrough fixture", () => {
  for (const name of allFixtures) {
    const report = readFixture(name);
    assert.equal(validateDevicePassthrough(report), report, name);
  }
});

test("rejects an unavailable capability with no reason", () => {
  const report = readFixture("device-passthrough.requires-privileged-helper.json");
  delete capability(report, "usb-passthrough").prerequisite;

  // The entire point of this report is that a "no" arrives with a reason attached.
  assert.throws(() => validateDevicePassthrough(report), /prerequisite/);
});

test("rejects an available capability that carries a prerequisite", () => {
  const report = readFixture("device-passthrough.requires-privileged-helper.json");
  capability(report, "network-usermode-nat").prerequisite = "needs something";

  assert.throws(() => validateDevicePassthrough(report), /must not carry a prerequisite/);
});

test("rejects an available capability that offers an alternative to itself", () => {
  const report = readFixture("device-passthrough.requires-privileged-helper.json");
  capability(report, "network-usermode-nat").alternative = "use something else";

  assert.throws(() => validateDevicePassthrough(report), /alternative to itself/);
});

test("rejects isAvailable drifting from state", () => {
  const report = readFixture("device-passthrough.requires-privileged-helper.json");
  capability(report, "usb-passthrough").isAvailable = true;

  assert.throws(() => validateDevicePassthrough(report), /must agree with/);
});

test("rejects a privileged-helper state that does not set the flag", () => {
  const report = readFixture("device-passthrough.requires-privileged-helper.json");
  capability(report, "network-bridged").requiresPrivilegedHelper = false;

  assert.throws(() => validateDevicePassthrough(report), /requiresPrivilegedHelper/);
});

test("rejects the flag on a state that is not about privileges", () => {
  const report = readFixture("device-passthrough.usb-host-not-built-in.json");
  capability(report, "usb-passthrough").requiresPrivilegedHelper = true;

  // A build with no usb-host has a different problem from a build that cannot get access, and
  // conflating them sends someone chasing privileges when they need a different QEMU.
  assert.throws(() => validateDevicePassthrough(report), /must agree with its state/);
});

test("rejects an unrecognized state", () => {
  const report = readFixture("device-passthrough.requires-privileged-helper.json");
  capability(report, "usb-passthrough").state = "comingSoon";

  assert.throws(() => validateDevicePassthrough(report), /Unsupported device passthrough state/);
});

test("rejects a report that drops a capability instead of reporting it unavailable", () => {
  const report = readFixture("device-passthrough.requires-privileged-helper.json");
  report.capabilities = report.capabilities.filter((entry) => entry.id !== "network-bridged");

  // Omitting a gap makes it disappear from the answer, which is the opposite of what this report is for.
  assert.throws(() => validateDevicePassthrough(report), /must cover network-bridged/);
});

test("rejects duplicate capability ids", () => {
  const report = readFixture("device-passthrough.requires-privileged-helper.json");
  report.capabilities.push({ ...capability(report, "network-bridged") });

  assert.throws(() => validateDevicePassthrough(report), /duplicate id/);
});

test("rejects a report claiming the shipping network mode is unavailable", () => {
  const report = readFixture("device-passthrough.requires-privileged-helper.json");
  const nat = capability(report, "network-usermode-nat");
  nat.state = "requiresPrivilegedHelper";
  nat.isAvailable = false;
  nat.requiresPrivilegedHelper = true;
  nat.prerequisite = "root";

  // If usermode NAT is unavailable the guest has no network at all, which is a much larger problem
  // than a missing passthrough mode and must not be reported as one of them.
  assert.throws(() => validateDevicePassthrough(report), /shipping default/);
});

test("rejects asserting USB availability when QEMU was never probed", () => {
  const report = readFixture("device-passthrough.qemu-unprobed.json");
  const usb = capability(report, "usb-passthrough");
  usb.state = "requiresPrivilegedHelper";
  usb.requiresPrivilegedHelper = true;

  assert.throws(() => validateDevicePassthrough(report), /unknown when QEMU was not probed/);
});

test("rejects leaving USB unknown after QEMU was probed", () => {
  const report = readFixture("device-passthrough.requires-privileged-helper.json");
  const usb = capability(report, "usb-passthrough");
  usb.state = "unknown";
  usb.requiresPrivilegedHelper = false;

  assert.throws(() => validateDevicePassthrough(report), /resolved when QEMU was probed/);
});

test("rejects a non-https reference", () => {
  const report = readFixture("device-passthrough.requires-privileged-helper.json");
  capability(report, "usb-passthrough").reference = "see the QEMU tracker";

  // A reference exists so a reader can check the claim rather than trust it.
  assert.throws(() => validateDevicePassthrough(report), /https URL/);
});

test("rejects a decision that does not name the privileged helper mechanism", () => {
  const report = readFixture("device-passthrough.requires-privileged-helper.json");
  report.privilegedHelperDecision = "Not supported. Running QEMU under sudo is refused.";

  assert.throws(() => validateDevicePassthrough(report), /privileged helper mechanism/);
});

test("rejects a decision that leaves the sudo shortcut unaddressed", () => {
  const report = readFixture("device-passthrough.requires-privileged-helper.json");
  report.privilegedHelperDecision = "This needs a privileged helper that Veil does not ship.";

  // Left unsaid, someone will reach for it, and it would put a user-controlled command line and a
  // network-reachable guest behind root.
  assert.throws(() => validateDevicePassthrough(report), /rule out running QEMU under sudo/);
});

test("rejects next actions that omit the sudo warning", () => {
  const report = readFixture("device-passthrough.requires-privileged-helper.json");
  report.nextActions = report.nextActions.filter((action) => !/sudo/i.test(action));

  assert.throws(() => validateDevicePassthrough(report), /warn against running QEMU under sudo/);
});

test("rejects presenting the blocker as pending implementation work", () => {
  const report = readFixture("device-passthrough.requires-privileged-helper.json");
  report.nextActions = report.nextActions.map((action) =>
    action.includes("open product decision")
      ? "USB passthrough is not implemented yet. Do not run QEMU under sudo."
      : action
  );

  // A contributor reading "not implemented yet" would start writing host code, and no amount of it
  // closes this.
  assert.throws(() => validateDevicePassthrough(report), /open decision/);
});

test("rejects an unknown capability that does not say how to resolve it", () => {
  const report = readFixture("device-passthrough.qemu-unprobed.json");
  report.nextActions = report.nextActions.filter((action) => !action.includes("qemu-doctor"));

  assert.throws(() => validateDevicePassthrough(report), /qemu-doctor/);
});

test("rejects hiding the alternative for an unavailable capability", () => {
  const report = readFixture("device-passthrough.requires-privileged-helper.json");
  report.nextActions = report.nextActions.filter((action) => !action.startsWith("USB device passthrough:"));

  // Telling a user what they cannot do without telling them what they can is the failure this catches.
  assert.throws(() => validateDevicePassthrough(report), /surface the alternative for usb-passthrough/);
});

test("rejects an empty nextActions list", () => {
  const report = readFixture("device-passthrough.requires-privileged-helper.json");
  report.nextActions = [];

  assert.throws(() => validateDevicePassthrough(report), /non-empty array/);
});

test("rejects a report of the wrong kind", () => {
  const report = readFixture("device-passthrough.requires-privileged-helper.json");
  report.kind = "vmSharedFolderStatus";

  assert.throws(() => validateDevicePassthrough(report), /Unsupported device passthrough kind/);
});
