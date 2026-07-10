import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import test from "node:test";

import { validateNotificationProof } from "../src/validate-notification-proof.mjs";

function readFixture(name) {
  return JSON.parse(readFileSync(new URL(`../fixtures/${name}`, import.meta.url), "utf8"));
}

test("validates proved Windows notification proof", () => {
  const report = readFixture("notification-proof.proved.json");

  validateNotificationProof(report, { requireProved: true });

  assert.equal(report.status, "proved");
  assert.equal(report.notification.type, "notification.received");
});

test("validates unavailable Windows notification proof", () => {
  const report = readFixture("notification-proof.unavailable.json");

  validateNotificationProof(report);

  assert.equal(report.status, "unavailable");
  assert.equal(report.notification, undefined);
});

test("require-proved rejects unavailable notification proof", () => {
  const result = spawnSync(
    process.execPath,
    [new URL("../src/validate-notification-proof.mjs", import.meta.url).pathname, "--require-proved"],
    {
      input: readFileSync(new URL("../fixtures/notification-proof.unavailable.json", import.meta.url)),
      encoding: "utf8"
    }
  );

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /notification proof is not proved/);
});

test("rejects proved reports without notification evidence", () => {
  const report = readFixture("notification-proof.proved.json");
  delete report.notification;

  assert.throws(
    () => validateNotificationProof(report),
    /notification must be an object/
  );
});
