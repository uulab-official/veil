import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { validateQEMUPlan } from "../src/validate-qemu-plan.mjs";

const fixture = JSON.parse(
  readFileSync(new URL("../fixtures/windows-arm-install-plan.json", import.meta.url), "utf8")
);

describe("QEMU boot plan harness", () => {
  it("accepts the Windows Arm install plan fixture", () => {
    assert.equal(validateQEMUPlan(fixture), fixture);
  });

  it("rejects plans that are not local", () => {
    assert.throws(
      () => validateQEMUPlan({ ...fixture, isServerBacked: true }),
      /non-server-backed/
    );
  });

  it("rejects plans without HVF acceleration", () => {
    const plan = {
      ...fixture,
      arguments: fixture.arguments.filter((argument) => argument !== "hvf")
    };

    assert.throws(() => validateQEMUPlan(plan), /-accel hvf/);
  });

  it("rejects plans without read-only installer media", () => {
    const plan = {
      ...fixture,
      arguments: fixture.arguments.map((argument) =>
        argument.startsWith("if=none,id=installer")
          ? "if=none,id=installer,media=disk,file=/Users/test/Downloads/Win11.iso"
          : argument
      )
    };

    assert.throws(() => validateQEMUPlan(plan), /read-only cdrom/);
  });
});
