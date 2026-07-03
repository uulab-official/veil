import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

import { validateMVPProof } from "../src/validate-mvp-proof.mjs";

function readFixture(name) {
  return JSON.parse(readFileSync(new URL(`../fixtures/${name}`, import.meta.url), "utf8"));
}

test("validates proved MVP proof fixture", () => {
  const report = readFixture("mvp-proof.proved.json");

  assert.equal(validateMVPProof(report), report);
});

test("validates unavailable MVP proof fixture", () => {
  const report = readFixture("mvp-proof.unavailable.json");

  assert.equal(validateMVPProof(report), report);
});

test("validates saved MVP proof path", () => {
  const report = readFixture("mvp-proof.proved.json");
  report.savedProofPath = "/Users/test/Library/Application Support/Veil/Diagnostics/MVP Proof/notepad-proof.json";

  assert.equal(validateMVPProof(report), report);
});

test("rejects proved MVP proof without coherence evidence", () => {
  const report = readFixture("mvp-proof.proved.json");
  delete report.coherence;

  assert.throws(
    () => validateMVPProof(report),
    /coherence proof evidence/
  );
});

test("rejects proved MVP proof without connected wait evidence", () => {
  const report = readFixture("mvp-proof.proved.json");
  report.wait.status = "unavailable";

  assert.throws(
    () => validateMVPProof(report),
    /connected guest wait/
  );
});

test("rejects stale post-input frame evidence", () => {
  const report = readFixture("mvp-proof.proved.json");
  report.coherence.postInputFrame.sequence = report.coherence.initialFrame.sequence;

  assert.throws(
    () => validateMVPProof(report),
    /postInputFrame\.sequence/
  );
});
