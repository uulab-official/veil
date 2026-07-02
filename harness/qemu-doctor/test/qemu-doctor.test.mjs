import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { validateQEMUDoctor } from "../src/validate-qemu-doctor.mjs";

const blockedFixture = JSON.parse(
  readFileSync(new URL("../fixtures/qemu-doctor.blocked.json", import.meta.url), "utf8")
);

describe("QEMU doctor harness", () => {
  it("accepts the blocked readiness fixture", () => {
    assert.equal(validateQEMUDoctor(blockedFixture), blockedFixture);
  });

  it("rejects reports that are not local", () => {
    assert.throws(
      () => validateQEMUDoctor({ ...blockedFixture, isServerBacked: true }),
      /non-server-backed/
    );
  });

  it("rejects blocked checks when the overall state is ready", () => {
    assert.throws(
      () => validateQEMUDoctor({ ...blockedFixture, overallState: "ready" }),
      /must be blocked/
    );
  });

  it("rejects blocked reports without recovery guidance", () => {
    assert.throws(
      () => validateQEMUDoctor({ ...blockedFixture, nextActions: ["Look at the logs."] }),
      /actionable recovery guidance/
    );
  });

  it("rejects reports without a TPM emulator check", () => {
    assert.throws(
      () => validateQEMUDoctor({
        ...blockedFixture,
        checks: blockedFixture.checks.filter((check) => check.id !== "tpm-emulator")
      }),
      /tpm-emulator/
    );
  });

  it("rejects reports without a Secure Boot check", () => {
    assert.throws(
      () => validateQEMUDoctor({
        ...blockedFixture,
        checks: blockedFixture.checks.filter((check) => check.id !== "secure-boot")
      }),
      /secure-boot/
    );
  });
});
