import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { validateQEMUSmoke } from "../src/validate-qemu-smoke.mjs";

const uefiShellFixture = JSON.parse(
  readFileSync(new URL("../fixtures/qemu-smoke.uefi-shell.json", import.meta.url), "utf8")
);

describe("QEMU smoke harness", () => {
  it("accepts the UEFI shell fallback fixture", () => {
    assert.equal(validateQEMUSmoke(uefiShellFixture), uefiShellFixture);
  });

  it("rejects unknown outcomes", () => {
    assert.throws(
      () => validateQEMUSmoke({ ...uefiShellFixture, outcome: "maybeBooted" }),
      /Unsupported QEMU smoke outcome/
    );
  });

  it("rejects UEFI shell reports without shell evidence", () => {
    assert.throws(
      () => validateQEMUSmoke({ ...uefiShellFixture, evidence: ["boot-image-timeout"] }),
      /uefi-shell evidence/
    );
  });

  it("rejects unsafe durations", () => {
    assert.throws(
      () => validateQEMUSmoke({ ...uefiShellFixture, durationSeconds: 300 }),
      /between 5 and 120/
    );
  });

  it("rejects reports without a console screenshot path", () => {
    const { consoleScreenshotPath: _path, ...report } = uefiShellFixture;

    assert.throws(
      () => validateQEMUSmoke(report),
      /consoleScreenshotPath/
    );
  });

  it("rejects reports without recovery guidance", () => {
    const { nextActions: _actions, ...report } = uefiShellFixture;

    assert.throws(
      () => validateQEMUSmoke(report),
      /nextActions/
    );
  });
});
