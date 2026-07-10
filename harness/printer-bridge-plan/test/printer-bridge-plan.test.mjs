import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import test from "node:test";

import { validatePrinterBridgePlan } from "../src/validate-printer-bridge-plan.mjs";

function readFixture(name) {
  return JSON.parse(readFileSync(new URL(`../fixtures/${name}`, import.meta.url), "utf8"));
}

test("validates Windows printer bridge plan", () => {
  const plan = readFixture("printer-bridge-plan.json");

  validatePrinterBridgePlan(plan);

  assert.equal(plan.mode, "manual-ipp-experiment");
  assert.equal(plan.hostAddress, "10.0.2.2");
  assert.match(plan.windowsAddPrinterCommand, /Add-Printer/);
});

test("CLI validator accepts a valid printer bridge plan", () => {
  const result = spawnSync(
    process.execPath,
    [new URL("../src/validate-printer-bridge-plan.mjs", import.meta.url).pathname],
    {
      input: readFileSync(new URL("../fixtures/printer-bridge-plan.json", import.meta.url)),
      encoding: "utf8"
    }
  );

  assert.equal(result.status, 0, result.stderr);
});

test("rejects printer bridge plans that drift away from QEMU host IPP", () => {
  const plan = readFixture("printer-bridge-plan.json");
  plan.ippEndpoint = "http://localhost:631/printers/Office%20Printer";

  assert.throws(
    () => validatePrinterBridgePlan(plan),
    /ippEndpoint/
  );
});

test("rejects Windows setup without Add-Printer IppURL", () => {
  const plan = readFixture("printer-bridge-plan.json");
  plan.windowsAddPrinterCommand = "Add-Printer -Name 'Veil Mac Printer'";

  assert.throws(
    () => validatePrinterBridgePlan(plan),
    /Add-Printer -IppURL/
  );
});

test("rejects plans that claim support without test-page proof", () => {
  const plan = readFixture("printer-bridge-plan.json");
  plan.limitations = ["Automatic printer support is ready."];

  assert.throws(
    () => validatePrinterBridgePlan(plan),
    /live proof/
  );
});
