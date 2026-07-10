import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

import { validateCoherenceProof } from "../src/validate-coherence-proof.mjs";

test("validates coherence proof fixture", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/coherence-proof.notepad.json", import.meta.url), "utf8"));

  assert.equal(validateCoherenceProof(report), report);
});

test("validates saved coherence proof path", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/coherence-proof.notepad.json", import.meta.url), "utf8"));
  report.savedProofPath = "/Users/test/Library/Application Support/Veil/Diagnostics/Coherence Proof/notepad-proof.json";

  assert.equal(validateCoherenceProof(report), report);
});

test("rejects stale post-input frame sequence", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/coherence-proof.notepad.json", import.meta.url), "utf8"));
  report.postInputFrame.sequence = report.initialFrame.sequence;

  assert.throws(
    () => validateCoherenceProof(report),
    /postInputFrame\.sequence/
  );
});

test("rejects mismatched post-input frame latency freshness", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/coherence-proof.notepad.json", import.meta.url), "utf8"));
  report.postInputFrameLatency.elapsedMilliseconds = 5200;
  report.postInputFrameLatency.isWithinFreshBudget = false;
  report.postInputFrameLatency.isWithinStaleTimeout = true;
  report.postInputFrameLatency.recommendedAction = "measure-again";

  assert.throws(
    () => validateCoherenceProof(report),
    /postInputFrameLatency\.isWithinStaleTimeout/
  );
});

test("rejects proof without mouse click evidence", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/coherence-proof.notepad.json", import.meta.url), "utf8"));
  report.input.mouseEventsPosted = ["move"];

  assert.throws(
    () => validateCoherenceProof(report),
    /mouseEventsPosted/
  );
});

test("rejects proof without host clipboard evidence", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/coherence-proof.notepad.json", import.meta.url), "utf8"));
  report.input.clipboardOrigin = "guest";

  assert.throws(
    () => validateCoherenceProof(report),
    /clipboardOrigin/
  );
});
