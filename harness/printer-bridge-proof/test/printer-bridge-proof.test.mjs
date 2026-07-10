import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import test from "node:test";

import { validatePrinterBridgeProof } from "../src/validate-printer-bridge-proof.mjs";

function readFixture(name) {
  return JSON.parse(readFileSync(new URL(`../fixtures/${name}`, import.meta.url), "utf8"));
}

test("validates Windows printer bridge proof", () => {
  const report = readFixture("printer-bridge-proof.json");

  validatePrinterBridgeProof(report);

  assert.equal(report.status, "proved");
  assert.equal(report.plan.mode, "manual-ipp-experiment");
});

test("CLI validator accepts a valid printer bridge proof", () => {
  const result = spawnSync(
    process.execPath,
    [new URL("../src/validate-printer-bridge-proof.mjs", import.meta.url).pathname],
    {
      input: readFileSync(new URL("../fixtures/printer-bridge-proof.json", import.meta.url)),
      encoding: "utf8"
    }
  );

  assert.equal(result.status, 0, result.stderr);
});

test("rejects unproved printer bridge reports", () => {
  const report = readFixture("printer-bridge-proof.json");
  report.status = "unavailable";

  assert.throws(
    () => validatePrinterBridgeProof(report),
    /status must be proved/
  );
});

test("rejects non-QEMU host IPP endpoints", () => {
  const report = readFixture("printer-bridge-proof.json");
  report.plan.ippEndpoint = "http://localhost:631/printers/Office%20Printer";

  assert.throws(
    () => validatePrinterBridgeProof(report),
    /plan\.ippEndpoint/
  );
});

test("rejects saved proof outside Printer Proof diagnostics", () => {
  const report = readFixture("printer-bridge-proof.json");
  report.savedProofPath = "/tmp/printer-bridge-proof.json";

  assert.throws(
    () => validatePrinterBridgeProof(report),
    /savedProofPath/
  );
});
