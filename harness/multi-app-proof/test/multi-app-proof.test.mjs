import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

import { validateMultiAppProof } from "../src/validate-multi-app-proof.mjs";

function fixture() {
  return JSON.parse(readFileSync(new URL("../fixtures/multi-app-proof.complete.json", import.meta.url), "utf8"));
}

test("validates complete multi-app proof fixture", () => {
  const report = fixture();

  assert.equal(validateMultiAppProof(report), report);
});

test("validates complete multi-app proof with require-complete", () => {
  const report = fixture();

  assert.equal(validateMultiAppProof(report, { requireComplete: true }), report);
});

test("rejects duplicate app ids", () => {
  const report = fixture();
  report.appIds[2] = "winapp_calculator";
  report.results[2].appId = "winapp_calculator";

  assert.throws(
    () => validateMultiAppProof(report),
    /duplicates/
  );
});

test("rejects mismatched result counts", () => {
  const report = fixture();
  report.provedAppCount = 2;

  assert.throws(
    () => validateMultiAppProof(report),
    /provedAppCount/
  );
});

test("rejects mismatched latency action", () => {
  const report = fixture();
  report.results[0].latencyRecommendedAction = "none";

  assert.throws(
    () => validateMultiAppProof(report),
    /latencyRecommendedAction/
  );
});

test("accepts partial coverage unless complete proof is required", () => {
  const report = fixture();
  report.results[2] = {
    appId: "winapp_paint",
    status: "failed",
    proofKind: "coherence",
    errorMessage: "connection timeout"
  };
  report.provedAppCount = 2;
  report.failedAppCount = 1;
  report.coverageHealth = "partial";
  report.nextActions.push("Run `veil-vmctl guest-agent-wait --json --wait-seconds 30` and retry `veil-vmctl multi-app-proof --json --require-complete` after the Windows app connection is live.");

  assert.equal(validateMultiAppProof(report), report);
  assert.throws(
    () => validateMultiAppProof(report, { requireComplete: true }),
    /coverageHealth must be complete/
  );
});
