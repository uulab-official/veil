import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

import { validateVMSnapshots } from "../src/validate-vm-snapshots.mjs";

function readFixture(name) {
  return JSON.parse(readFileSync(new URL(`../fixtures/${name}`, import.meta.url), "utf8"));
}

test("validates unsupported, created, and restored snapshot fixtures", () => {
  for (const name of [
    "vm-snapshots.unsupported-raw-disk.json",
    "vm-snapshots.created.json",
    "vm-snapshots.restored.json"
  ]) {
    const report = readFixture(name);
    assert.equal(validateVMSnapshots(report), report, name);
  }
});

test("rejects an unsupported raw disk report without a conversion command", () => {
  const report = readFixture("vm-snapshots.unsupported-raw-disk.json");
  delete report.capability.conversionCommand;

  assert.throws(() => validateVMSnapshots(report), /conversionCommand/);
});

test("rejects an unsupported report that omits the suspend alternative", () => {
  const report = readFixture("vm-snapshots.unsupported-raw-disk.json");
  report.nextActions = report.nextActions.filter((action) => !action.includes("vm-suspend"));

  assert.throws(() => validateVMSnapshots(report), /vm-suspend/);
});

test("rejects an unsupported report that hides the qemu-img conversion step", () => {
  const report = readFixture("vm-snapshots.unsupported-raw-disk.json");
  report.nextActions = report.nextActions.filter((action) => !action.includes("qemu-img convert"));

  assert.throws(() => validateVMSnapshots(report), /qemu-img convert/);
});

test("rejects an unsupported report that lists snapshots anyway", () => {
  const report = readFixture("vm-snapshots.unsupported-raw-disk.json");
  report.snapshots = [
    {
      id: "1",
      tag: "before-update",
      vmStateSize: "4.02 GiB",
      createdAt: "2026-07-29 10:19:58",
      vmClock: "00:14:07.221"
    }
  ];

  assert.throws(() => validateVMSnapshots(report), /must not list snapshots/);
});

test("rejects a supported capability whose disk is not qcow2", () => {
  const report = readFixture("vm-snapshots.created.json");
  report.capability.systemDiskFormat = "raw";

  assert.throws(() => validateVMSnapshots(report), /qcow2 system disk/);
});

test("rejects a succeeded create that does not list the new snapshot", () => {
  const report = readFixture("vm-snapshots.created.json");
  report.snapshots = [];

  assert.throws(() => validateVMSnapshots(report), /newly created snapshot tag/);
});

test("rejects a succeeded delete that still lists the deleted snapshot", () => {
  const report = readFixture("vm-snapshots.created.json");
  report.action = "delete";
  report.nextActions = ["Run veil-vmctl vm-snapshot-list --json to confirm the snapshot was removed."];

  assert.throws(() => validateVMSnapshots(report), /still list the deleted snapshot tag/);
});

test("rejects a mutating snapshot action that succeeded without a running VM", () => {
  const report = readFixture("vm-snapshots.created.json");
  report.vmState = "stopped";

  assert.throws(() => validateVMSnapshots(report), /requires a running VM state/);
});

test("rejects a restored snapshot that skips guest agent reconnection", () => {
  const report = readFixture("vm-snapshots.restored.json");
  report.nextActions = ["Open Veil.app."];

  assert.throws(() => validateVMSnapshots(report), /guest-agent/);
});

test("rejects snapshot tags containing whitespace", () => {
  const report = readFixture("vm-snapshots.created.json");
  report.requestedTag = "before update";
  report.snapshots[0].tag = "before update";

  assert.throws(() => validateVMSnapshots(report), /whitespace|requestedTag/);
});

test("rejects duplicate snapshot tags", () => {
  const report = readFixture("vm-snapshots.created.json");
  report.snapshots.push({ ...report.snapshots[0], id: "2" });

  assert.throws(() => validateVMSnapshots(report), /duplicate tag/);
});

test("requires an error message on failed snapshot actions", () => {
  const report = readFixture("vm-snapshots.created.json");
  report.status = "failed";

  assert.throws(() => validateVMSnapshots(report), /errorMessage/);
});
