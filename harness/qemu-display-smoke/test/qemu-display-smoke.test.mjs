import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

import { validateQEMUDisplaySmoke } from "../src/validate-qemu-display-smoke.mjs";

test("validates qemu display smoke fixture", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/qemu-display-smoke.pass.json", import.meta.url), "utf8"));

  assert.equal(validateQEMUDisplaySmoke(report), report);
});

test("rejects reports without loopback endpoint", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/qemu-display-smoke.pass.json", import.meta.url), "utf8"));
  report.endpoint = "0.0.0.0:5907";

  assert.throws(
    () => validateQEMUDisplaySmoke(report),
    /loopback VNC endpoint/
  );
});

test("rejects reports with mismatched RGBA byte count", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/qemu-display-smoke.pass.json", import.meta.url), "utf8"));
  report.pixelByteCount = 4;

  assert.throws(
    () => validateQEMUDisplaySmoke(report),
    /RGBA dimensions/
  );
});
