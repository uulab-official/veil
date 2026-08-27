import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

import { validateVMSession } from "../src/validate-vm-session.mjs";

function readFixture(name) {
  return JSON.parse(readFileSync(new URL(`../fixtures/${name}`, import.meta.url), "utf8"));
}

test("validates suspended, resumed, and stopped VM session fixtures", () => {
  for (const name of ["vm-session.suspended.json", "vm-session.resumed.json", "vm-session.stopped.json"]) {
    const report = readFixture(name);
    assert.equal(validateVMSession(report), report, name);
  }
});

test("rejects a suspended session whose memory state lives under Diagnostics", () => {
  const report = readFixture("vm-session.suspended.json");
  report.persistence.stateFilePath =
    "/Users/example/Library/Application Support/Veil/Diagnostics/QEMU Suspend/Windows 11 Arm.vmsave";

  assert.throws(() => validateVMSession(report), /Diagnostics/);
});

test("rejects a completed suspend without durable evidence", () => {
  const report = readFixture("vm-session.suspended.json");
  delete report.persistence.machineFingerprint;

  assert.throws(() => validateVMSession(report), /machineFingerprint/);
});

test("rejects a completed resume that still advertises the consumed session", () => {
  const report = readFixture("vm-session.resumed.json");
  report.canResume = true;
  report.persistence.suspendedAt = "2026-07-29T09:14:52Z";

  assert.throws(() => validateVMSession(report), /clear the suspended session evidence/);
});

test("rejects canResume without stored suspended session evidence", () => {
  const report = readFixture("vm-session.suspended.json");
  delete report.persistence.suspendedAt;

  assert.throws(() => validateVMSession(report), /suspendedAt|stored suspended session evidence/);
});

test("rejects canSuspend on a VM that is not running", () => {
  const report = readFixture("vm-session.stopped.json");
  report.canSuspend = true;
  report.nextActions.push("Run veil-vmctl vm-suspend --json to persist the Windows session.");

  assert.throws(() => validateVMSession(report), /canSuspend requires a running VM state/);
});

test("rejects a session that claims to be both suspendable and resumable", () => {
  const report = readFixture("vm-session.suspended.json");
  report.canSuspend = true;

  assert.throws(() => validateVMSession(report), /at the same time/);
});

test("rejects unsupported persistence that still advertises a state file", () => {
  const report = readFixture("vm-session.stopped.json");
  report.persistence.isSupported = false;
  report.persistence.mode = "unsupported";

  assert.throws(() => validateVMSession(report), /must not advertise a memory state file path/);
});

test("requires an error message on failed session actions", () => {
  const report = readFixture("vm-session.suspended.json");
  report.status = "failed";
  report.state = "running";
  report.canResume = false;
  report.nextActions = ["Run veil-vmctl vm-session-status --json to re-read the current session state."];

  assert.throws(() => validateVMSession(report), /errorMessage/);
});

test("rejects a resumable session without a vm-resume next action", () => {
  const report = readFixture("vm-session.suspended.json");
  report.nextActions = ["Open Veil.app."];

  assert.throws(() => validateVMSession(report), /vm-resume/);
});

test("rejects a stopped session without a start next action", () => {
  const report = readFixture("vm-session.stopped.json");
  report.nextActions = ["Open Veil.app."];

  assert.throws(() => validateVMSession(report), /start next action/);
});
