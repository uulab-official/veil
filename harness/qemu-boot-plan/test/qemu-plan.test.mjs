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
        argument.includes("id=installer")
          ? "driver=raw,file.driver=file,file.locking=off,file.filename=/Users/test/Downloads/Win11.iso,if=none,id=installer,media=disk"
          : argument
      )
    };

    assert.throws(() => validateQEMUPlan(plan), /read-only cdrom/);
  });

  it("rejects plans without declared Arm UEFI firmware", () => {
    const plan = {
      ...fixture,
      arguments: fixture.arguments.filter((argument) => argument !== "-bios" && argument !== fixture.firmwarePath)
    };

    assert.throws(() => validateQEMUPlan(plan), /-bios/);
  });

  it("rejects plans without guest agent port forwarding", () => {
    const plan = {
      ...fixture,
      arguments: fixture.arguments.map((argument) =>
        argument === "user,id=net0,hostfwd=tcp::18444-:18444" ? "user,id=net0" : argument
      )
    };

    assert.throws(() => validateQEMUPlan(plan), /hostfwd=tcp::18444-:18444/);
  });

  it("rejects plans without TPM 2.0 emulator devices", () => {
    const plan = {
      ...fixture,
      arguments: fixture.arguments.filter((argument) =>
        !argument.includes("chrtpm") && !argument.includes("tpm0")
      )
    };

    assert.throws(() => validateQEMUPlan(plan), /TPM 2.0 emulator/);
  });
});
